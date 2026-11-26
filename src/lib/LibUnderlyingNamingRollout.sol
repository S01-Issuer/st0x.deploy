// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";

import {ICorporateActionsV1} from "../interface/ICorporateActionsV1.sol";
import {IStoxUnderlyingV1} from "../interface/IStoxUnderlyingV1.sol";
import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";
import {LibBeaconInvariants} from "./LibBeaconInvariants.sol";
import {LibProdTokenConfig, TokenConfig} from "./LibProdTokenConfig.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "./LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "./LibTokenInvariants.sol";
import {LibSecurity} from "./LibSecurity.sol";

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

/// @notice The rollout's batches were cut for the networks before 0G
/// (`LibStoxDeployNetworks.networksBeforeZerog`), whose tables share Base's row
/// order, and for 0G. Any other chain's table can hold another token set, so
/// the rollout refuses it.
/// @param chainId The chain id.
error UnderlyingNamingNotCutForChain(uint256 chainId);

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
/// 2. The rename batch: `setUnderlying(ticker, underlyingName)` on every
///    production vault of the chain, scheduled with the beacon batch as its
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

    /// @notice The receipt-vault implementation every in-use receipt-vault beacon serves before the beacon batch (the
    /// 0.1.30 vault); the beacon pre-flight refuses any other.
    address internal constant RECEIPT_VAULT_FROM_IMPLEMENTATION = LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30;

    /// @notice The wrapped-token-vault implementation every in-use wrapper beacon serves before the beacon batch (the
    /// 0.1.1 wrapper); the beacon pre-flight refuses any other.
    address internal constant WRAPPED_TOKEN_VAULT_FROM_IMPLEMENTATION = LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1;

    /// @notice Whether the implementation constants above alias a frozen, audited release; while false both schedule
    /// scripts refuse. The targets (`FACET`, `RECEIPT_VAULT_IMPLEMENTATION`, `WRAPPED_TOKEN_VAULT_IMPLEMENTATION` and
    /// their codehashes) alias the current-source candidate pins.
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
    bool internal constant DOWNSTREAM_ACCEPTS_NEW_SYMBOLS = true;

    /// @notice How many leading rows of the production token table this
    /// rollout renames on each network before 0G: tMSTR to tDIS. Fixed, so the
    /// rename operation's id does not move when a table grows once the batch
    /// is scheduled; a token added later gets its own `setUnderlying`
    /// operation.
    uint256 internal constant TOKEN_COUNT = 56;

    /// @notice How many leading rows of 0G's production token table this
    /// rollout renames: every token of 0G's token creation, tMSTR to tTPRO.
    /// Fixed for the same reason as `TOKEN_COUNT`.
    uint256 internal constant ZEROG_TOKEN_COUNT = 65;

    /// @notice The production tokens this rollout renames on the chain: the
    /// leading `tokenCount` rows of the chain's table. Reverts
    /// `NoTokenTableForChain` on a chain with no table and
    /// `UnderlyingNamingNotCutForChain` on a chain with a table that the
    /// rollout was not cut for.
    /// @param chainId The chain id.
    /// @return The chain's token instances.
    function tokens(uint256 chainId) internal pure returns (TokenInstance[] memory) {
        TokenInstance[] memory table = LibTokenInvariants.productionTokensForChainId(chainId);
        return leadingRows(chainId, table);
    }

    /// @notice Whether the rollout's rename and beacon batches were cut for
    /// `chainId`: one of the networks before 0G
    /// (`LibStoxDeployNetworks.networksBeforeZerog`), or 0G. `tokens` and
    /// `BuildExpectedState.renameMigration` both read this, so they agree.
    /// @param chainId The chain id.
    /// @return Whether the batches were cut for the chain.
    function cutForChain(uint256 chainId) internal pure returns (bool) {
        return chainId == LibSafeInvariants.ZEROG_CHAIN_ID
            || LibRainDeploy.hasChainId(
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.networksBeforeZerog()), chainId
        );
    }

    /// @notice How many leading rows of `chainId`'s production table the
    /// rollout renames: `ZEROG_TOKEN_COUNT` on 0G, `TOKEN_COUNT` on the
    /// networks before it. Reverts `UnderlyingNamingNotCutForChain` on any
    /// other chain.
    /// @param chainId The chain id.
    /// @return The row count.
    function tokenCount(uint256 chainId) internal pure returns (uint256) {
        if (!cutForChain(chainId)) revert UnderlyingNamingNotCutForChain(chainId);
        return chainId == LibSafeInvariants.ZEROG_CHAIN_ID ? ZEROG_TOKEN_COUNT : TOKEN_COUNT;
    }

    /// @notice The leading `tokenCount(chainId)` rows of `table`, so the
    /// rename id does not move when the table grows. Reverts
    /// `UnderlyingNamingNotCutForChain` as `tokenCount` does, and
    /// `UnderlyingNamingTokenTableShort` when the table has fewer rows.
    /// @param chainId The chain id.
    /// @param table The chain's token table.
    /// @return The leading rows.
    function leadingRows(uint256 chainId, TokenInstance[] memory table) internal pure returns (TokenInstance[] memory) {
        uint256 count = tokenCount(chainId);
        if (table.length < count) revert UnderlyingNamingTokenTableShort(chainId, count, table.length);
        // The table's leading `count` rows: shorten the array in place.
        assembly ("memory-safe") {
            mstore(table, count)
        }
        return table;
    }

    /// @notice Whether the rename batch renames the row at `tokenIndex` of
    /// `chainId`'s production table: one of the leading `tokenCount(chainId)`.
    /// @param chainId The chain id.
    /// @param tokenIndex The row's index in the chain's production table.
    /// @return Whether the rename batch renames it.
    function renamesRow(uint256 chainId, uint256 tokenIndex) internal pure returns (bool) {
        return tokenIndex < tokenCount(chainId);
    }

    /// @notice Every vault and wrapper behind the two beacons on the chain:
    /// the chain's token table, then tQSEP on Base.
    /// @param chainId The chain id.
    /// @return The tokens.
    function beaconTokens(uint256 chainId) internal pure returns (TokenInstance[] memory) {
        TokenInstance[] memory table = LibTokenInvariants.productionTokensForChainId(chainId);
        if (chainId != LibSafeInvariants.BASE_CHAIN_ID) return table;
        TokenInstance[] memory chainTokens = new TokenInstance[](table.length + 1);
        for (uint256 tokenIndex = 0; tokenIndex < table.length; tokenIndex++) {
            chainTokens[tokenIndex] = table[tokenIndex];
        }
        chainTokens[table.length] = LibTokenInvariants.qsepToken();
        return chainTokens;
    }

    /// @notice Every vault and wrapper behind the two beacons on the chain
    /// that the rename does not set: the table rows past the renamed ones,
    /// then tQSEP on Base.
    /// @param chainId The chain id.
    /// @return The tokens.
    function unrenamedTokens(uint256 chainId) internal pure returns (TokenInstance[] memory) {
        TokenInstance[] memory table = LibTokenInvariants.productionTokensForChainId(chainId);
        bool onBase = chainId == LibSafeInvariants.BASE_CHAIN_ID;
        uint256 count = onBase ? 1 : 0;
        for (uint256 tokenIndex = 0; tokenIndex < table.length; tokenIndex++) {
            if (!renamesRow(chainId, tokenIndex)) count++;
        }
        TokenInstance[] memory chainTokens = new TokenInstance[](count);
        uint256 next = 0;
        for (uint256 tokenIndex = 0; tokenIndex < table.length; tokenIndex++) {
            if (!renamesRow(chainId, tokenIndex)) chainTokens[next++] = table[tokenIndex];
        }
        if (onBase) chainTokens[next] = LibTokenInvariants.qsepToken();
        return chainTokens;
    }

    /// @notice Every vault's and wrapper's name and symbol, in a fixed order:
    /// vault name, vault symbol, wrapper name, wrapper symbol, per token.
    /// @param chainTokens The tokens.
    /// @return The values read.
    function metadata(TokenInstance[] memory chainTokens) internal view returns (string[] memory) {
        string[] memory values = new string[](chainTokens.length * 4);
        for (uint256 tokenIndex = 0; tokenIndex < chainTokens.length; tokenIndex++) {
            values[tokenIndex * 4] = IERC20Metadata(chainTokens[tokenIndex].receiptVault).name();
            values[tokenIndex * 4 + 1] = IERC20Metadata(chainTokens[tokenIndex].receiptVault).symbol();
            values[tokenIndex * 4 + 2] = IERC20Metadata(chainTokens[tokenIndex].wrappedTokenVault).name();
            values[tokenIndex * 4 + 3] = IERC20Metadata(chainTokens[tokenIndex].wrappedTokenVault).symbol();
        }
        return values;
    }

    /// @notice The vault or wrapper `metadata` read at `index`.
    /// @param chainTokens The tokens.
    /// @param index The index into `metadata`.
    /// @return The vault or wrapper.
    function metadataToken(TokenInstance[] memory chainTokens, uint256 index) internal pure returns (address) {
        TokenInstance memory token = chainTokens[index / 4];
        return index % 4 < 2 ? token.receiptVault : token.wrappedTokenVault;
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
    /// underlyingName)` on every production vault of the chain, in table
    /// order.
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
            payloads[tokenIndex] =
                abi.encodeCall(IStoxUnderlyingV1.setUnderlying, (config.underlying, config.underlyingName));
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
            !LibSecurity.tickerWellFormed(bytes(config.underlying))
                || !LibSecurity.nameWellFormed(bytes(config.underlyingName))
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

