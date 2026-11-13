// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    ICorporateActionsV1,
    ACTION_TYPE_STOCK_SPLIT_V1,
    BALANCE_MIGRATION_TYPES_MASK
} from "../interface/ICorporateActionsV1.sol";
import {LibCorporateAction, SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../lib/LibCorporateAction.sol";
import {ActionDoesNotExist} from "../error/ErrCorporateAction.sol";
import {
    CorporateActionNode,
    CompletionFilter,
    LibCorporateActionNode,
    NODE_NONE
} from "../lib/LibCorporateActionNode.sol";
import {LibStockSplit} from "../lib/LibStockSplit.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.3.11/src/lib/LibDecimalFloat.sol";
import {IAuthorizeV1} from "rain-vats-0.2.20/src/interface/IAuthorizeV1.sol";
import {OffchainAssetReceiptVault} from "rain-vats-0.2.20/src/abstract/OffchainAssetReceiptVault.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {IStoxUnderlyingV2} from "../interface/IStoxUnderlyingV2.sol";
import {IOwnable} from "../interface/IOwnable.sol";
import {LibUnderlying, ST0X_NAME_SUFFIX} from "../lib/LibUnderlying.sol";
import {
    MalformedUnderlyingTicker,
    MalformedUnderlyingName,
    MalformedUnderlyingIsin
} from "../error/ErrUnderlying.sol";
import {IStoxTokenConfigV1, StoxTokenConfigV1, STOX_TOKEN_CONFIG_V1_TAG} from "../interface/IStoxTokenConfigV1.sol";
import {
    InvalidStoxTokenConfigTag,
    NonCanonicalStoxTokenConfig,
    MalformedAssetId,
    MalformedListingTicker,
    MalformedListingName,
    StoxTokenAlreadyInitialized
} from "../error/ErrStoxTokenConfig.sol";
import {LibStoxTokenConfig} from "../lib/LibStoxTokenConfig.sol";
import {LibUnderlyingSnapshot} from "../lib/LibUnderlyingSnapshot.sol";
import {UNDERLYING_SNAPSHOT_ROOT} from "../generated/LibUnderlyingSnapshotCode.sol";
import {LibERC20Storage} from "../lib/LibERC20Storage.sol";
import {
    OffchainAssetReceiptVaultConfigV3,
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG
} from "rain-vats-0.2.20/src/interface/IOffchainAssetReceiptVaultV1.sol";

/// @title StoxCorporateActionsFacet
/// @notice Diamond facet implementing the corporate action linked list.
/// @dev MUST be delegatecalled by an `OffchainAssetReceiptVault`-derived
/// contract. Every external entry point carries the `onlyDelegatecalled`
/// modifier, which reads the immutable `_SELF` (set to `address(this)` at
/// construction time) and reverts with `FacetMustBeDelegatecalled` if the
/// call is not running under delegatecall. This makes the "cannot run
/// standalone" property explicit rather than relying on the incidental
/// fact that `OffchainAssetReceiptVault(address(this)).authorizer()` fails
/// to resolve on a standalone deployment — the guard fires even for pure
/// view getters that would not otherwise reach the authorizer lookup.
///
/// Corporate-action storage lives at the ERC-7201 namespace
/// `rain.storage.corporate-action.1` (see `LibCorporateAction`). The facet
/// also implements `IStoxUnderlyingV2`, whose override lives at
/// `rain.storage.underlying.1` (see `LibUnderlying`). Any future external
/// entry points added here (e.g. list traversal) must also carry
/// `onlyDelegatecalled`.
contract StoxCorporateActionsFacet is ICorporateActionsV1, IStoxUnderlyingV2, IStoxTokenConfigV1 {
    /// @notice Thrown when a function is called directly on the standalone
    /// facet deployment rather than via delegatecall from the vault.
    error FacetMustBeDelegatecalled();

    /// @dev The address of this facet contract at deployment time, captured
    /// in the constructor and baked into bytecode as an immutable. Under a
    /// legitimate delegatecall from the vault, `address(this)` resolves to
    /// the vault's address and differs from `_SELF`; a direct call to the
    /// standalone facet has `address(this) == _SELF` and is rejected by
    /// `onlyDelegatecalled`. Constructor remains parameterless for Zoltu
    /// deterministic deployment.
    /// _SELF follows the OZ UUPSUpgradeable pattern for delegatecall guards.
    // slither-disable-next-line naming-convention
    address private immutable _SELF;

    constructor() {
        _SELF = address(this);
    }

    /// @dev Rejects direct calls to the standalone facet deployment. Every
    /// external entry point — including view getters — must carry this
    /// modifier so the facet has no callable surface outside of a vault's
    /// delegatecall context. Mirrors the pattern used by
    /// `OpenZeppelin UUPSUpgradeable.onlyProxy`.
    modifier onlyDelegatecalled() {
        if (address(this) == _SELF) revert FacetMustBeDelegatecalled();
        _;
    }

    /// @inheritdoc ICorporateActionsV1
    function completedActionCount() external view override onlyDelegatecalled returns (uint256) {
        return LibCorporateAction.countCompleted();
    }

    /// @inheritdoc ICorporateActionsV1
    // The authorizer call sits before any state write. Re-entry through it
    // is bounded by the trust model documented at the contract level: the
    // authorizer is the canonical permission boundary, and any re-entry
    // through it is, by definition, an authorized sequence of calls. Each
    // re-entrant `schedule` independently captures its own `actionId`
    // from `s.nodes.length - 1` and the linked-list insert is atomic per
    // call, so interleaved invocations cannot corrupt the list.
    // slither-disable-next-line reentrancy-events
    function scheduleCorporateAction(bytes32 typeHash, uint64 effectiveTime, bytes calldata parameters)
        external
        override
        onlyDelegatecalled
        returns (uint256)
    {
        authorizeAction(msg.sender, SCHEDULE_CORPORATE_ACTION, abi.encode(typeHash, effectiveTime, parameters));
        uint256 actionType = LibCorporateAction.resolveActionType(typeHash, parameters);
        uint256 actionId = LibCorporateAction.schedule(actionType, effectiveTime, parameters);
        emit CorporateActionScheduled(msg.sender, actionId, actionType, effectiveTime);
        return actionId;
    }

    /// @inheritdoc ICorporateActionsV1
    // Same trust model as `scheduleCorporateAction`. The outer call's
    // `actionId` is captured from calldata before `authorizeAction`, so a
    // re-entrant cancel during the authorizer callback can only act on
    // whatever index the (trusted) authorizer chooses to cancel — it
    // cannot redirect the outer call's target.
    // slither-disable-next-line reentrancy-events
    function cancelCorporateAction(uint256 actionId) external override onlyDelegatecalled {
        authorizeAction(msg.sender, CANCEL_CORPORATE_ACTION, abi.encode(actionId));
        LibCorporateAction.cancel(actionId);
        emit CorporateActionCancelled(msg.sender, actionId);
    }

    /// @inheritdoc ICorporateActionsV1
    function latestActionOfType(uint256 mask, CompletionFilter filter)
        external
        view
        override
        onlyDelegatecalled
        returns (uint256, uint256, uint64)
    {
        // False positive: tuple pass-through — `return lib.tupleFn(...)` re-emits every
        // component as this function's own return, nothing is discarded.
        // slither-disable-next-line unused-return
        return LibCorporateActionNode.latestActionOfType(mask, filter);
    }

    /// @inheritdoc ICorporateActionsV1
    function earliestActionOfType(uint256 mask, CompletionFilter filter)
        external
        view
        override
        onlyDelegatecalled
        returns (uint256, uint256, uint64)
    {
        // False positive: tuple pass-through — `return lib.tupleFn(...)` re-emits every
        // component as this function's own return, nothing is discarded.
        // slither-disable-next-line unused-return
        return LibCorporateActionNode.earliestActionOfType(mask, filter);
    }

    /// @inheritdoc ICorporateActionsV1
    function nextOfType(uint256 fromId, uint256 mask, CompletionFilter filter)
        external
        view
        override
        onlyDelegatecalled
        returns (uint256, uint256, uint64)
    {
        // False positive: tuple pass-through — `return lib.tupleFn(...)` re-emits every
        // component as this function's own return, nothing is discarded.
        // slither-disable-next-line unused-return
        return LibCorporateActionNode.nextActionOfType(fromId, mask, filter);
    }

    /// @inheritdoc ICorporateActionsV1
    function prevOfType(uint256 fromId, uint256 mask, CompletionFilter filter)
        external
        view
        override
        onlyDelegatecalled
        returns (uint256, uint256, uint64)
    {
        // False positive: tuple pass-through — `return lib.tupleFn(...)` re-emits every
        // component as this function's own return, nothing is discarded.
        // slither-disable-next-line unused-return
        return LibCorporateActionNode.prevActionOfType(fromId, mask, filter);
    }

    /// @inheritdoc ICorporateActionsV1
    function getActionParameters(uint256 actionId) external view override onlyDelegatecalled returns (bytes memory) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        // Bounds check covers `NODE_NONE` (= type(uint256).max) implicitly:
        // `s.nodes.length` is bounded by realistic schedule cadence, so any
        // sentinel value comparable to max uint256 is >= length.
        if (actionId >= s.nodes.length) revert ActionDoesNotExist(actionId);
        // `effectiveTime == 0` means the slot was never populated or the
        // action was cancelled; both are surfaced as nonexistent so the
        // facet's view of the schedule matches what list walks see.
        if (s.nodes[actionId].effectiveTime == 0) revert ActionDoesNotExist(actionId);
        return s.nodes[actionId].parameters;
    }

    /// @inheritdoc ICorporateActionsV1
    function cumulativeBalanceMultiplierSinceGenesis() external view override onlyDelegatecalled returns (Float) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        // Identity: the canonical one exported by rain-math-float.
        Float cumulative = LibDecimalFloat.FLOAT_ONE;
        // Same selection as `LibRebase.migratedBalance`: completed
        // balance-migration nodes only, in chronological order from the
        // head of the list (`NODE_NONE` start is head-inclusive, so the
        // bootstrap node is visited — it is identity and skipped below).
        uint256 nodeIndex =
            LibCorporateActionNode.nextOfType(NODE_NONE, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED);
        while (nodeIndex != NODE_NONE) {
            // Init nodes are identity for balance migration; only stock
            // splits carry a multiplier payload.
            if (s.nodes[nodeIndex].actionType == ACTION_TYPE_STOCK_SPLIT_V1) {
                cumulative =
                    LibDecimalFloat.mul(cumulative, LibStockSplit.decodeParametersV1(s.nodes[nodeIndex].parameters));
            }
            nodeIndex =
                LibCorporateActionNode.nextOfType(nodeIndex, BALANCE_MIGRATION_TYPES_MASK, CompletionFilter.COMPLETED);
        }
        return cumulative;
    }

    /// @inheritdoc IStoxUnderlyingV2
    function underlyingSymbol() external view override onlyDelegatecalled returns (string memory) {
        (string memory ticker,,) = resolveUnderlying();
        return ticker;
    }

    /// @inheritdoc IStoxUnderlyingV2
    function underlyingName() external view override onlyDelegatecalled returns (string memory) {
        (, string memory underlying,) = resolveUnderlying();
        return underlying;
    }

    /// @inheritdoc IStoxUnderlyingV2
    function underlyingIsin() external view override onlyDelegatecalled returns (string memory) {
        (,, string memory isin) = resolveUnderlying();
        return isin;
    }

    /// @notice The vault's ERC-20 name, forwarded here by `StoxReceiptVault`.
    /// @return The name.
    function name() external view onlyDelegatecalled returns (string memory) {
        (, string memory underlying,) = resolveUnderlying();
        if (bytes(underlying).length == 0) return LibERC20Storage.getStorage()._name;
        return string.concat(underlying, ST0X_NAME_SUFFIX);
    }

    /// @notice The vault's ERC-20 symbol, forwarded here by `StoxReceiptVault`.
    /// @return The symbol.
    function symbol() external view onlyDelegatecalled returns (string memory) {
        (string memory ticker,,) = resolveUnderlying();
        if (bytes(ticker).length == 0) return LibERC20Storage.getStorage()._symbol;
        return string.concat("t", ticker);
    }

    /// @inheritdoc IStoxUnderlyingV2
    /// @dev Gated on the vault's `owner()` rather than the authorizer: the
    /// values are the vault's ERC-20 metadata, an owner surface like
    /// `setAuthorizer`. `owner()` is a call back into the vault, which
    /// resolves it from its own selector table without reaching this facet.
    function setUnderlying(string calldata newSymbol, string calldata newName, string calldata newIsin)
        external
        override
        onlyDelegatecalled
    {
        if (msg.sender != IOwnable(address(this)).owner()) {
            revert OwnableUpgradeable.OwnableUnauthorizedAccount(msg.sender);
        }
        if (!LibUnderlying.tickerWellFormed(bytes(newSymbol))) revert MalformedUnderlyingTicker(newSymbol);
        if (!LibUnderlying.nameWellFormed(bytes(newName))) revert MalformedUnderlyingName(newName);
        if (!LibUnderlying.isinWellFormed(newIsin)) revert MalformedUnderlyingIsin(newIsin);

        LibUnderlying.UnderlyingStorage storage s = LibUnderlying.getStorage();
        emit UnderlyingSet(msg.sender, s.symbol, s.name, s.isin, newSymbol, newName, newIsin);
        s.symbol = newSymbol;
        s.name = newName;
        s.isin = newIsin;
        s.timestamp = uint256(block.timestamp);
    }

    /// @inheritdoc IStoxTokenConfigV1
    function initializeStoxToken(bytes calldata data) external override onlyDelegatecalled returns (bytes memory) {
        if (!LibStoxTokenConfig.isUninitialized()) revert StoxTokenAlreadyInitialized();
        if (data.length < 0x20) revert InvalidStoxTokenConfigTag(bytes32(0));
        bytes32 tag = abi.decode(data, (bytes32));
        if (tag != STOX_TOKEN_CONFIG_V1_TAG) revert InvalidStoxTokenConfigTag(tag);
        (, StoxTokenConfigV1 memory config) = abi.decode(data, (bytes32, StoxTokenConfigV1));
        if (keccak256(abi.encode(tag, config)) != keccak256(data)) revert NonCanonicalStoxTokenConfig();
        if (!LibUnderlying.isinWellFormed(config.assetId)) revert MalformedAssetId(config.assetId);
        if (!LibUnderlying.tickerWellFormed(bytes(config.listingTicker))) {
            revert MalformedListingTicker(config.listingTicker);
        }
        if (!LibUnderlying.nameWellFormed(bytes(config.listingName))) revert MalformedListingName(config.listingName);

        LibStoxTokenConfig.StoxTokenConfigStorage storage s = LibStoxTokenConfig.getStorage();
        s.assetId = config.assetId;
        s.listingTicker = config.listingTicker;
        s.listingName = config.listingName;
        s.region = config.region;

        emit StoxTokenInitialized(msg.sender, config);

        return abi.encode(
            OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
            OffchainAssetReceiptVaultConfigV3({
                name: string.concat(config.listingName, ST0X_NAME_SUFFIX),
                symbol: string.concat("t", config.listingTicker),
                authority: config.authority,
                rbacName: config.rbacName,
                receiptBeaconName: config.receiptBeaconName,
                metadata: config.metadata
            })
        );
    }

    /// @dev Reverts when the snapshot root has no code. Empty for a legacy vault
    /// with no override.
    function resolveUnderlying() internal view returns (string memory, string memory, string memory) {
        LibUnderlyingSnapshot.Lookup memory row = LibUnderlyingSnapshot.lookup(UNDERLYING_SNAPSHOT_ROOT, address(this));
        LibUnderlying.UnderlyingStorage storage o = LibUnderlying.getStorage();
        if (o.timestamp > row.asOf) return (o.symbol, o.name, o.isin);
        if (row.found) return (row.ticker, row.name, row.isin);
        if (o.timestamp > 0) return (o.symbol, o.name, o.isin);
        LibStoxTokenConfig.StoxTokenConfigStorage storage c = LibStoxTokenConfig.getStorage();
        return (c.listingTicker, c.listingName, c.assetId);
    }

    /// @dev Authorize via the vault's authorizer. Since this facet is
    /// delegatecalled by the vault, `address(this)` is the vault and we can
    /// access its storage to find the authorizer. The `data` argument is
    /// forwarded so authorizers can apply per-action policy (e.g. rate-limiting
    /// by multiplier magnitude or action type).
    /// @param user The address requesting the action (typically `msg.sender`).
    /// @param permission The bytes32 permission constant identifying the action.
    /// @param data ABI-encoded action context. For schedule:
    /// `abi.encode(bytes32 typeHash, uint64 effectiveTime, bytes parameters)`.
    /// For cancel: `abi.encode(uint256 actionId)`.
    function authorizeAction(address user, bytes32 permission, bytes memory data) internal {
        IAuthorizeV1 auth = OffchainAssetReceiptVault(payable(address(this))).authorizer();
        auth.authorize(user, permission, data);
    }
}
