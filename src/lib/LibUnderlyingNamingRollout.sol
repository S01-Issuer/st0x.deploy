// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";

import {ICorporateActionsV1} from "../interface/ICorporateActionsV1.sol";
import {IStoxUnderlyingV2} from "../interface/IStoxUnderlyingV2.sol";
import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {LibBeaconInvariants} from "./LibBeaconInvariants.sol";
import {LibProdTokenConfig, TokenConfig} from "./LibProdTokenConfig.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "./LibTokenInvariants.sol";
import {LibUnderlying} from "./LibUnderlying.sol";

/// @notice The implementations this rollout names are not a frozen, audited
/// release yet, so nothing may deploy them or schedule a beacon onto them.
error UnderlyingNamingReleaseNotFrozen();

/// @notice The chain's production token table is shorter than the token set
/// this rollout was written for.
/// @param chainId The chain id.
/// @param expected The rollout's token count for the chain.
/// @param actual The table's length.
error UnderlyingNamingTokenTableShort(uint256 chainId, uint256 expected, uint256 actual);

/// @notice A token's live receipt-vault symbol is not `"t" + underlying`, so
/// the ticker this rollout would set does not belong to that vault.
/// @param underlying The token's ticker key.
/// @param vault The token's receipt vault.
/// @param symbol The vault's live symbol.
error TickerNotBoundToVault(string underlying, address vault, string symbol);

/// @notice A row's ticker or underlying name is not in the shape the rename
/// sets: the ticker is 1 to 16 of `A-Z`, `0-9` and `.`, and the name is
/// non-empty, has no `"`, `\` or control byte (the receipt's `uri()` builds
/// JSON from the vault symbol without escaping), and does not already carry
/// the ST0x suffix.
/// @param underlying The row's ticker.
/// @param underlyingName The row's underlying name.
error MalformedUnderlying(string underlying, string underlyingName);

/// @notice The downstream services are not yet confirmed to accept the
/// renamed wrapper symbols, so the rename may not be scheduled.
error DownstreamNotReadyForRename();

/// @title LibUnderlyingNamingRollout
/// @notice The two timelock operations that roll out the underlying ticker
/// and name on a chain, reconstructed from repo state so the scripts that
/// schedule them, the script that executes them and the tests cannot drift
/// onto different operation ids.
///
/// 1. The beacon batch: the chain's in-use wrapped-token-vault beacon and
///    receipt-vault beacon move to the implementations below, then a
///    read-only facet call on one production vault. A delegatecall into a
///    facet address with no code reverts with `CorporateActionsFacetNotDeployed`
///    in the new vault implementation, so the whole batch rolls back if the
///    facet is missing at execution.
/// 2. The rename batch: `setUnderlying(ticker, underlyingName, isin)` on
///    every production vault of the chain, scheduled with the beacon batch as its
///    predecessor, so the timelock refuses to execute it first.
///
/// The implementations are the current-source candidate pins. They are the
/// one place this rollout names its bytecode; a rollout is dispatched only
/// against a frozen, audited release, so these move to that release's pins
/// before any dispatch.
library LibUnderlyingNamingRollout {
    /// @notice Salt of the beacon batch.
    bytes32 internal constant BEACON_SALT = keccak256("st0x.underlying-naming.beacons.1");

    /// @notice Salt of the rename batch.
    bytes32 internal constant RENAME_SALT = keccak256("st0x.underlying-naming.rename.1");

    /// @notice The corporate-actions facet the new vault implementation pins.
    address internal constant FACET = LibProdDeployCurrent.STOX_CORPORATE_ACTIONS_FACET;

    /// @notice The facet's runtime codehash.
    bytes32 internal constant FACET_CODEHASH = LibProdDeployCurrent.STOX_CORPORATE_ACTIONS_FACET_CODEHASH;

    /// @notice The receipt-vault implementation the vault beacon moves to.
    address internal constant RECEIPT_VAULT_IMPLEMENTATION = LibProdDeployCurrent.STOX_RECEIPT_VAULT;

    /// @notice Its runtime codehash.
    bytes32 internal constant RECEIPT_VAULT_CODEHASH = LibProdDeployCurrent.STOX_RECEIPT_VAULT_CODEHASH;

    /// @notice The wrapped-token-vault implementation the wrapper beacon moves
    /// to.
    address internal constant WRAPPED_TOKEN_VAULT_IMPLEMENTATION = LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT;

    /// @notice Its runtime codehash.
    bytes32 internal constant WRAPPED_TOKEN_VAULT_CODEHASH = LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT_CODEHASH;

    /// @notice Whether the implementation constants above alias a frozen,
    /// audited release. They alias the current-source candidate pins, so the
    /// step-1 deploy and both schedule scripts refuse. The PR that sets this
    /// also: re-points the six implementation constants and the step-1 deploy
    /// at the release; pins each chain's `beaconOperationId` and
    /// `renameOperationId` as literals, so a later row edit cannot move a
    /// scheduled batch. Each schedule script's Safe bundle ends in its root-line
    /// record; no record rides in a timelock batch.
    bool internal constant RELEASE_FROZEN = false;

    /// @notice Whether st0x.liquidity, st0x.pricing, st0x-oracle-server and
    /// the st0x.registry token lists accept both `wt<TICKER>` and
    /// `<TICKER>s` in production. The rename cannot be undone, so the rename
    /// script refuses unless this is set. Set on this evidence (RAI-4172):
    /// - st0x.liquidity accepts both symbols since
    ///   ST0x-Technology/st0x.liquidity#1973 (commit b70fe2950679), live in
    ///   production as release v1.29.0 (RAI-4168).
    /// - st0x.pricing and st0x-oracle-server never read an on-chain
    ///   `symbol()`, so they need no change (RAI-4169 and RAI-4170 closed as
    ///   not needed).
    /// - The st0x.registry token lists keep `symbol` = `wt<TICKER>` and carry
    ///   the additive `nextSymbol` / `nextName`
    ///   (ST0x-Technology/st0x.registry#117).
    /// The same PR moved the head-fork tests that pin the initialized names
    /// (`testConfigMatchesLiveBase`, `testWrappedDerivationHoldsOnBase` and
    /// the cross-chain parity pin `StoxCrossChainParityTest`) to accept the
    /// renamed values too, so they stay green as each chain executes the
    /// rename. The `wt*` symbol pins in `LibTokenInvariants.addresses.t.sol`
    /// fork at a pinned pre-rename block; they accept `<TICKER>s` too, so a
    /// later block bump does not break them on the symbol alone.
    bool internal constant DOWNSTREAM_ACCEPTS_NEW_SYMBOLS = true;

    /// @notice How many leading rows of each chain's production token table
    /// this rollout renames: tMSTR to tDIS, on every chain. Fixed, so the
    /// rename operation's id does not move when a table grows once the batch
    /// is scheduled; a token added later gets its own `setUnderlying`
    /// operation.
    uint256 internal constant TOKEN_COUNT = 56;

    /// @notice The production tokens this rollout renames on the chain: the
    /// leading `TOKEN_COUNT` rows of the chain's table. Reverts
    /// `NoTokenTableForChain` on a chain with no table.
    /// @param chainId The chain id.
    /// @return The chain's token instances.
    function tokens(uint256 chainId) internal pure returns (TokenInstance[] memory) {
        return leadingRows(chainId, LibTokenInvariants.productionTokensForChainId(chainId));
    }

    /// @notice The leading `TOKEN_COUNT` rows of `table`, so the rename id
    /// does not move when the table grows. Reverts
    /// `UnderlyingNamingTokenTableShort` when it has fewer.
    /// @param chainId The chain id, for the error.
    /// @param table The chain's token table.
    /// @return The leading rows.
    function leadingRows(uint256 chainId, TokenInstance[] memory table) internal pure returns (TokenInstance[] memory) {
        uint256 count = TOKEN_COUNT;
        if (table.length < count) revert UnderlyingNamingTokenTableShort(chainId, count, table.length);
        // The table's leading `count` rows: shorten the array in place.
        assembly ("memory-safe") {
            mstore(table, count)
        }
        return table;
    }

    /// @notice The chain's in-use receipt-vault beacon.
    /// @param chainId The chain id.
    /// @return The beacon.
    function receiptVaultBeacon(uint256 chainId) internal view returns (address) {
        return LibBeaconInvariants.prodBeaconsForChainId(chainId)[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX];
    }

    /// @notice The chain's in-use wrapped-token-vault beacon.
    /// @param chainId The chain id.
    /// @return The beacon.
    function wrappedTokenVaultBeacon(uint256 chainId) internal view returns (address) {
        return LibBeaconInvariants.prodBeaconsForChainId(chainId)[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX];
    }

    /// @notice The beacon batch's calls: the wrapper beacon upgrade, the vault
    /// beacon upgrade, then the facet probe on the chain's first production
    /// vault.
    /// @param chainId The chain id.
    /// @return targets The call targets.
    /// @return values The call values, all zero.
    /// @return payloads The calldata.
    function beaconBatch(uint256 chainId)
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        targets = new address[](3);
        values = new uint256[](3);
        payloads = new bytes[](3);
        targets[0] = wrappedTokenVaultBeacon(chainId);
        payloads[0] = abi.encodeCall(UpgradeableBeacon.upgradeTo, (WRAPPED_TOKEN_VAULT_IMPLEMENTATION));
        targets[1] = receiptVaultBeacon(chainId);
        payloads[1] = abi.encodeCall(UpgradeableBeacon.upgradeTo, (RECEIPT_VAULT_IMPLEMENTATION));
        targets[2] = tokens(chainId)[0].receiptVault;
        payloads[2] = abi.encodeCall(ICorporateActionsV1.completedActionCount, ());
    }

    /// @notice The rename batch's calls: `setUnderlying(underlying,
    /// underlyingName, isin)` on every production vault of the chain, in
    /// table order.
    /// @param chainId The chain id.
    /// @return targets The call targets.
    /// @return values The call values, all zero.
    /// @return payloads The calldata.
    function renameBatch(uint256 chainId)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        TokenInstance[] memory chainTokens = tokens(chainId);
        targets = new address[](chainTokens.length);
        values = new uint256[](chainTokens.length);
        payloads = new bytes[](chainTokens.length);
        for (uint256 tokenIndex = 0; tokenIndex < chainTokens.length; tokenIndex++) {
            TokenConfig memory config = LibProdTokenConfig.configOf(chainTokens[tokenIndex].underlying);
            targets[tokenIndex] = chainTokens[tokenIndex].receiptVault;
            payloads[tokenIndex] = abi.encodeCall(
                IStoxUnderlyingV2.setUnderlying, (config.underlying, config.underlyingName, config.isin)
            );
        }
    }

    /// @notice Reverts unless every production vault of the chain reports
    /// `"t" + underlying` as its live symbol, binding each ticker the rename
    /// batch sets to the vault it lands on.
    /// @param chainId The chain id.
    function assertTickersBound(uint256 chainId) internal view {
        TokenInstance[] memory chainTokens = tokens(chainId);
        for (uint256 tokenIndex = 0; tokenIndex < chainTokens.length; tokenIndex++) {
            TokenInstance memory token = chainTokens[tokenIndex];
            string memory symbol = IERC20Metadata(token.receiptVault).symbol();
            if (keccak256(bytes(symbol)) != keccak256(bytes(string.concat("t", token.underlying)))) {
                revert TickerNotBoundToVault(token.underlying, token.receiptVault, symbol);
            }
        }
    }

    /// @notice Reverts unless every row the chain's rename sets is well
    /// formed (see `MalformedUnderlying`).
    /// @param chainId The chain id.
    function assertUnderlyingsWellFormed(uint256 chainId) internal pure {
        TokenInstance[] memory chainTokens = tokens(chainId);
        TokenConfig[] memory rows = new TokenConfig[](chainTokens.length);
        for (uint256 tokenIndex = 0; tokenIndex < chainTokens.length; tokenIndex++) {
            rows[tokenIndex] = LibProdTokenConfig.configOf(chainTokens[tokenIndex].underlying);
        }
        assertRowsWellFormed(rows);
    }

    /// @notice Reverts `MalformedUnderlying` on the first row of `rows` that is
    /// not well formed.
    /// @param rows The rows.
    function assertRowsWellFormed(TokenConfig[] memory rows) internal pure {
        for (uint256 rowIndex = 0; rowIndex < rows.length; rowIndex++) {
            assertUnderlyingWellFormed(rows[rowIndex]);
        }
    }

    /// @notice Reverts `MalformedUnderlying` unless `config`'s ticker and
    /// underlying name are well formed.
    /// @param config The row.
    function assertUnderlyingWellFormed(TokenConfig memory config) internal pure {
        if (
            !LibUnderlying.tickerWellFormed(bytes(config.underlying))
                || !LibUnderlying.nameWellFormed(bytes(config.underlyingName))
        ) {
            revert MalformedUnderlying(config.underlying, config.underlyingName);
        }
    }

    /// @notice The beacon batch's operation id on `timelock`.
    /// @param timelock The chain's timelock.
    /// @param chainId The chain id.
    /// @return The operation id.
    function beaconOperationId(address timelock, uint256 chainId) internal view returns (bytes32) {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = beaconBatch(chainId);
        return
            TimelockController(payable(timelock)).hashOperationBatch(targets, values, payloads, bytes32(0), BEACON_SALT);
    }

    /// @notice The rename batch's operation id on `timelock`. Its predecessor
    /// is the beacon batch.
    /// @param timelock The chain's timelock.
    /// @param chainId The chain id.
    /// @return The operation id.
    function renameOperationId(address timelock, uint256 chainId) internal view returns (bytes32) {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = renameBatch(chainId);
        return TimelockController(payable(timelock))
            .hashOperationBatch(targets, values, payloads, beaconOperationId(timelock, chainId), RENAME_SALT);
    }

    /// @notice `scheduleBatch` calldata for the beacon batch.
    /// @param chainId The chain id.
    /// @return The calldata.
    function scheduleBeaconCalldata(uint256 chainId) internal view returns (bytes memory) {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = beaconBatch(chainId);
        return abi.encodeCall(
            TimelockController.scheduleBatch,
            (targets, values, payloads, bytes32(0), BEACON_SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
        );
    }

    /// @notice `scheduleBatch` calldata for the rename batch.
    /// @param timelock The chain's timelock.
    /// @param chainId The chain id.
    /// @return The calldata.
    function scheduleRenameCalldata(address timelock, uint256 chainId) internal view returns (bytes memory) {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = renameBatch(chainId);
        return abi.encodeCall(
            TimelockController.scheduleBatch,
            (
                targets,
                values,
                payloads,
                beaconOperationId(timelock, chainId),
                RENAME_SALT,
                LibTimelockInvariants.TIMELOCK_MIN_DELAY
            )
        );
    }
}

