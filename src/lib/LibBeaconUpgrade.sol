// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";

import {ICorporateActionsV1} from "../interface/ICorporateActionsV1.sol";
import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";
import {LibBeaconInvariants} from "./LibBeaconInvariants.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "./LibTokenInvariants.sol";
import {LibStoxMigrations} from "./LibStoxMigrations.sol";
import {ScriptDeclaration} from "../interface/IStoxScript.sol";

/// @notice The implementations this rollout names are not a frozen, audited
/// release yet, so nothing may deploy them or schedule a beacon onto them.
error BeaconUpgradeReleaseNotFrozen();

/// @title LibBeaconUpgrade
/// @notice The beacon batch that upgrades the wrapper and receipt-vault beacons on a chain,
/// reconstructed from repo state so the script that schedules it and the
/// tests cannot drift onto a different operation id: the chain's in-use
/// wrapped-token-vault beacon and receipt-vault beacon move to the
/// implementations below, then a read-only facet call on one production
/// vault, then the batch's root-line record. A delegatecall into a facet
/// address with no code reverts with `CorporateActionsFacetNotDeployed` in the
/// new vault implementation, so the whole batch rolls back if the facet is
/// missing at execution.
///
/// The implementations are the current-source candidate pins. They are the
/// one place this rollout names its bytecode; a rollout is dispatched only
/// against a frozen, audited release, so these move to that release's pins
/// before any dispatch.
library LibBeaconUpgrade {
    /// @notice Salt of the beacon batch.
    bytes32 internal constant BEACON_SALT = keccak256("st0x.beacon-upgrade.1");

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

    /// @notice Whether the implementation constants above alias a frozen, audited release; while false the schedule
    /// script refuses. The targets (`FACET`, `RECEIPT_VAULT_IMPLEMENTATION`, `WRAPPED_TOKEN_VAULT_IMPLEMENTATION` and
    /// their codehashes) alias the current-source candidate pins.
    bool internal constant RELEASE_FROZEN = false;

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
    /// vault, then the batch's root-line record (`beaconDeclaration`).
    /// @param chainId The chain id.
    /// @return The call targets.
    /// @return The call values, all zero.
    /// @return The calldata.
    function beaconBatch(uint256 chainId) internal view returns (address[] memory, uint256[] memory, bytes[] memory) {
        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory payloads = new bytes[](4);
        targets[0] = wrappedTokenVaultBeacon(chainId);
        payloads[0] = abi.encodeCall(UpgradeableBeacon.upgradeTo, (WRAPPED_TOKEN_VAULT_IMPLEMENTATION));
        targets[1] = receiptVaultBeacon(chainId);
        payloads[1] = abi.encodeCall(UpgradeableBeacon.upgradeTo, (RECEIPT_VAULT_IMPLEMENTATION));
        targets[2] = LibTokenInvariants.productionTokensForChainId(chainId)[0].receiptVault;
        payloads[2] = abi.encodeCall(ICorporateActionsV1.completedActionCount, ());
        (targets[3], payloads[3]) = LibStoxMigrations.recordCall(beaconDeclaration());
        return (targets, values, payloads);
    }

    /// @notice The beacon batch's root-line record, its last call, written by
    /// the timelock as an approved root delegate.
    /// @return The declaration.
    function beaconDeclaration() internal pure returns (ScriptDeclaration memory) {
        return ScriptDeclaration({
            id: LibStoxMigrations.SCHEDULE_BEACON_UPGRADE,
            onto: LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK,
            history: false
        });
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
}
