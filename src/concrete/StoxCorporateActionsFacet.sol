// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICorporateActionsV1} from "../interface/ICorporateActionsV1.sol";
import {LibCorporateAction, SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../lib/LibCorporateAction.sol";
import {ActionDoesNotExist} from "../error/ErrCorporateAction.sol";
import {
    CorporateActionNode,
    CompletionFilter,
    LibCorporateActionNode,
    NODE_NONE
} from "../lib/LibCorporateActionNode.sol";
import {IAuthorizeV1} from "rain-vats-0.1.4/src/interface/IAuthorizeV1.sol";
import {OffchainAssetReceiptVault} from "rain-vats-0.1.4/src/concrete/vault/OffchainAssetReceiptVault.sol";

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
/// Storage lives at the ERC-7201 namespace `rain.storage.corporate-action.1`
/// (see `LibCorporateAction`). Any future external entry points added here
/// (e.g. list traversal) must also carry `onlyDelegatecalled`.
contract StoxCorporateActionsFacet is ICorporateActionsV1 {
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
        returns (uint256 actionId)
    {
        authorizeAction(msg.sender, SCHEDULE_CORPORATE_ACTION, abi.encode(typeHash, effectiveTime, parameters));
        uint256 actionType = LibCorporateAction.resolveActionType(typeHash, parameters);
        actionId = LibCorporateAction.schedule(actionType, effectiveTime, parameters);
        emit CorporateActionScheduled(msg.sender, actionId, actionType, effectiveTime);
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
        returns (uint256 actionId, uint256 actionType, uint64 effectiveTime)
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
        returns (uint256 actionId, uint256 actionType, uint64 effectiveTime)
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
        returns (uint256 nextActionId, uint256 actionType, uint64 effectiveTime)
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
        returns (uint256 prevActionId, uint256 actionType, uint64 effectiveTime)
    {
        // False positive: tuple pass-through — `return lib.tupleFn(...)` re-emits every
        // component as this function's own return, nothing is discarded.
        // slither-disable-next-line unused-return
        return LibCorporateActionNode.prevActionOfType(fromId, mask, filter);
    }

    /// @inheritdoc ICorporateActionsV1
    function getActionParameters(uint256 actionId)
        external
        view
        override
        onlyDelegatecalled
        returns (bytes memory parameters)
    {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        // Bounds check covers `NODE_NONE` (= type(uint256).max) implicitly:
        // `s.nodes.length` is bounded by realistic schedule cadence, so any
        // sentinel value comparable to max uint256 is >= length.
        if (actionId >= s.nodes.length) revert ActionDoesNotExist(actionId);
        // `effectiveTime == 0` means the slot was never populated or the
        // action was cancelled; both are surfaced as nonexistent so the
        // facet's view of the schedule matches what list walks see.
        if (s.nodes[actionId].effectiveTime == 0) revert ActionDoesNotExist(actionId);
        parameters = s.nodes[actionId].parameters;
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
