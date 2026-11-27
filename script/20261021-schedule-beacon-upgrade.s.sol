// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.38/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";

import {StoxSafeBundleScript} from "../src/abstract/StoxSafeBundleScript.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {TokenInstance} from "../src/lib/LibTokenInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibBeaconUpgrade, BeaconUpgradeReleaseNotFrozen} from "../src/lib/LibBeaconUpgrade.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibUnderlyingSnapshot} from "../src/lib/LibUnderlyingSnapshot.sol";
import {LibSecurity} from "../src/lib/LibSecurity.sol";
import {LibProdTokenConfig, TokenConfig} from "../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenParams} from "../src/lib/LibProdTokenParams.sol";
import {PREFIX_BYTES_LENGTH} from "rain-datacontract-0.2.1/src/lib/LibDataContract.sol";
import {LibUnderlyingSnapshotCode, UNDERLYING_SNAPSHOT_ROOT} from "../src/generated/LibUnderlyingSnapshotCode.sol";

/// @notice An implementation the beacon batch points a beacon at does not
/// carry its pinned code on this chain. Deploy it first (rollout step 1).
/// @param implementation The implementation address.
/// @param expected The pinned codehash.
/// @param actual The codehash on chain.
error ImplementationNotDeployed(address implementation, bytes32 expected, bytes32 actual);

/// @notice The underlying snapshot root, or a shard it names, does not carry
/// its pinned code on this chain.
/// @param pointer The root or shard.
/// @param expected The pinned codehash.
/// @param actual The codehash on chain.
error UnderlyingSnapshotNotDeployed(address pointer, bytes32 expected, bytes32 actual);

/// @notice A beacon this batch upgrades already points at the target
/// implementation, so the batch has run on this chain.
/// @param beacon The beacon.
error BeaconAlreadyUpgraded(address beacon);

/// @notice The operation is already registered on the timelock: scheduling
/// it again would revert inside the Safe transaction.
/// @param id The operation id.
error OperationAlreadyScheduled(bytes32 id);

/// @notice After the bundle the operation is not pending, or is ready inside
/// its delay.
/// @param id The operation id.
error OperationNotPendingInsideDelay(bytes32 id);

/// @notice After execution a beacon does not point at its target.
/// @param beacon The beacon.
/// @param expected The target implementation.
/// @param actual The beacon's implementation.
error BeaconNotUpgraded(address beacon, address expected, address actual);

/// @notice A vault or wrapper does not read its resolved name or symbol after
/// the beacon batch.
/// @param token The vault or wrapper.
/// @param expected The resolved value.
/// @param afterUpgrade The value it reads.
error BeaconUpgradeWrongMetadata(address token, string expected, string afterUpgrade);

/// @notice This script's declaration: the beacon batch's own record, written
/// by the timelock at execution, after the Safe-owned Base vault handover.
/// @return The declaration.
function scheduleBeaconUpgradeDeclaration() pure returns (ScriptDeclaration memory) {
    return LibBeaconUpgrade.beaconDeclaration();
}

/// @title ScheduleBeaconUpgrade
/// @notice Authors the per-chain Safe bundle that SCHEDULES the
/// beacon upgrade batch on the chain's governance timelock (see
/// `LibBeaconUpgrade` for the calls). One Safe call:
/// `timelock.scheduleBatch(...)`, with the pinned 48h delay. The batch's last
/// call writes its root-line record.
///
/// Execution is not a Safe action: the timelock lets anyone execute a ready
/// operation (`20261021-execute-beacon-upgrade` does it from the CI deploy
/// key). The batch ends with a read-only facet call, so it reverts as a whole,
/// and stays Ready, if the facet has no code at execution.
///
/// Pre-flight refuses while `LibBeaconUpgrade.RELEASE_FROZEN` is
/// false: the implementations must be a frozen, audited release before a
/// beacon is scheduled onto them.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261021-schedule-beacon-upgrade` per chain, after the
/// implementations are deployed there.
contract ScheduleBeaconUpgrade is StoxSafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return scheduleBeaconUpgradeDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x beacon upgrade: schedule the wrapper and receipt-vault beacon upgrades";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261021-schedule-beacon-upgrade-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @notice The chain's governance timelock.
    /// @return The timelock.
    function timelock() internal view returns (address) {
        return LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    /// @notice Whether the implementations are a frozen, audited release.
    /// @return `LibBeaconUpgrade.RELEASE_FROZEN`.
    function releaseFrozen() internal pure virtual returns (bool) {
        return LibBeaconUpgrade.RELEASE_FROZEN;
    }

    /// @notice Reverts unless `implementation` carries `codehash`.
    /// @param implementation The implementation.
    /// @param codehash The pinned codehash.
    function assertDeployed(address implementation, bytes32 codehash) internal view {
        if (implementation.codehash != codehash) {
            revert ImplementationNotDeployed(implementation, codehash, implementation.codehash);
        }
    }

    /// @notice Reverts unless `pointer` carries the runtime code
    /// `creationCode` deploys.
    /// @param pointer The snapshot root or shard.
    /// @param creationCode Its generated creation code.
    function assertSnapshotDeployed(address pointer, bytes memory creationCode) internal view {
        // The runtime keeps the prefix's trailing STOP byte.
        uint256 runtimeStart = PREFIX_BYTES_LENGTH - 1;
        bytes32 expected;
        assembly ("memory-safe") {
            expected := keccak256(add(add(creationCode, 0x20), runtimeStart), sub(mload(creationCode), runtimeStart))
        }
        if (pointer.codehash != expected) revert UnderlyingSnapshotNotDeployed(pointer, expected, pointer.codehash);
    }

    /// @notice Reverts unless the snapshot root and every shard address read
    /// from it carry their pinned code.
    function assertUnderlyingSnapshotDeployed() internal view {
        assertSnapshotDeployed(UNDERLYING_SNAPSHOT_ROOT, LibUnderlyingSnapshotCode.ROOT_CREATION_CODE);
        address[] memory shards = LibUnderlyingSnapshot.shards(UNDERLYING_SNAPSHOT_ROOT);
        bytes[] memory shardCodes = LibUnderlyingSnapshotCode.shardCreationCodes();
        for (uint256 i = 0; i < shards.length; i++) {
            assertSnapshotDeployed(shards[i], shardCodes[i]);
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The release is frozen, the Safe and timelock are the pinned ones,
    /// the timelock owns the in-use beacons, the three implementations carry their pinned code, the
    /// underlying snapshot root and every shard it names carry their pinned code, the
    /// beacons have not moved and still serve their pinned from-implementations,
    /// the operation is not registered, and the root line is at this
    /// migration's `onto` and the timelock may write the batch's record.
    function preflight() internal view override {
        if (!releaseFrozen()) revert BeaconUpgradeReleaseNotFrozen();
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock(), chainSafe);
        LibStoxMigrations.assertNext(scheduleBeaconUpgradeDeclaration(), timelock());
        LibBeaconInvariants.assertProdBeaconsOwnedByChainTimelock(block.chainid);

        assertUnderlyingSnapshotDeployed();
        assertDeployed(LibBeaconUpgrade.FACET, LibBeaconUpgrade.FACET_CODEHASH);
        assertDeployed(LibBeaconUpgrade.RECEIPT_VAULT_IMPLEMENTATION, LibBeaconUpgrade.RECEIPT_VAULT_CODEHASH);
        assertDeployed(
            LibBeaconUpgrade.WRAPPED_TOKEN_VAULT_IMPLEMENTATION, LibBeaconUpgrade.WRAPPED_TOKEN_VAULT_CODEHASH
        );

        address vaultBeacon = LibBeaconUpgrade.receiptVaultBeacon(block.chainid);
        if (IBeacon(vaultBeacon).implementation() == LibBeaconUpgrade.RECEIPT_VAULT_IMPLEMENTATION) {
            revert BeaconAlreadyUpgraded(vaultBeacon);
        }
        address wrapperBeacon = LibBeaconUpgrade.wrappedTokenVaultBeacon(block.chainid);
        if (IBeacon(wrapperBeacon).implementation() == LibBeaconUpgrade.WRAPPED_TOKEN_VAULT_IMPLEMENTATION) {
            revert BeaconAlreadyUpgraded(wrapperBeacon);
        }
        // Each beacon must still serve the implementation this batch moves it
        // from, so a batch is never scheduled over an upgrade it does not know
        // about.
        bytes32[4] memory codehashes = LibBeaconInvariants.prodBeaconCodehashesForChainId(block.chainid);
        LibBeaconInvariants.assertBeaconInvariants(
            vaultBeacon,
            timelock(),
            LibBeaconUpgrade.RECEIPT_VAULT_FROM_IMPLEMENTATION,
            codehashes[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]
        );
        LibBeaconInvariants.assertBeaconInvariants(
            wrapperBeacon,
            timelock(),
            LibBeaconUpgrade.WRAPPED_TOKEN_VAULT_FROM_IMPLEMENTATION,
            codehashes[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX]
        );

        bytes32 id = LibBeaconUpgrade.beaconOperationId(timelock(), block.chainid);
        if (TimelockController(payable(timelock())).isOperation(id)) revert OperationAlreadyScheduled(id);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The schedule alone; the batch carries its own record.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({
            to: timelock(),
            value: 0,
            data: LibBeaconUpgrade.scheduleBeaconCalldata(block.chainid),
            operation: Enum.Operation.Call
        });
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Scheduled, pending and not ready inside the delay.
    function assertPostState() internal view override {
        TimelockController controller = TimelockController(payable(timelock()));
        bytes32 id = LibBeaconUpgrade.beaconOperationId(timelock(), block.chainid);
        if (!controller.isOperationPending(id) || controller.isOperationReady(id)) {
            revert OperationNotPendingInsideDelay(id);
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Executes the batch after the delay, as an address with no role,
    /// on a snapshot: both beacons point at their targets.
    function assertReversible() internal override {
        uint256 postBundle = vm.snapshotState();
        proveExecution();
        vm.revertToState(postBundle);
    }

    /// @notice The execution proof `assertReversible` runs. After the batch,
    /// every vault and wrapper behind the two beacons, the token table and
    /// tQSEP on Base, must read the `name()` and `symbol()` `expectedMetadata`
    /// resolves for it.
    function proveExecution() internal {
        TokenInstance[] memory chainTokens = LibBeaconUpgrade.beaconTokens(block.chainid);
        string[] memory before = LibBeaconUpgrade.metadata(chainTokens);
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibBeaconUpgrade.beaconBatch(block.chainid);
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.prank(address(0xdead));
        TimelockController(payable(timelock()))
            .executeBatch(targets, values, payloads, bytes32(0), LibBeaconUpgrade.BEACON_SALT);

        assertBeacon(
            LibBeaconUpgrade.wrappedTokenVaultBeacon(block.chainid), LibBeaconUpgrade.WRAPPED_TOKEN_VAULT_IMPLEMENTATION
        );
        assertBeacon(LibBeaconUpgrade.receiptVaultBeacon(block.chainid), LibBeaconUpgrade.RECEIPT_VAULT_IMPLEMENTATION);
        string[] memory expected = expectedMetadata(chainTokens, before);
        string[] memory afterUpgrade = LibBeaconUpgrade.metadata(chainTokens);
        for (uint256 i = 0; i < expected.length; i++) {
            if (keccak256(bytes(expected[i])) != keccak256(bytes(afterUpgrade[i]))) {
                revert BeaconUpgradeWrongMetadata(
                    LibBeaconUpgrade.metadataToken(chainTokens, i), expected[i], afterUpgrade[i]
                );
            }
        }
        console2.log("Execution proven: both beacons upgraded by a roleless executor after 48h, every name resolved");
    }

    /// @notice The `name()` and `symbol()` each vault and wrapper resolves
    /// after the batch, in `LibBeaconUpgrade.metadata` order. The underlying
    /// is the vault's snapshot row, else its table row's listing when the
    /// vault is at its listed address; the vault reads `LibSecurity.vaultName`
    /// / `LibSecurity.vaultSymbol` of it and the wrapper the vault's name /
    /// ticker + "s". A vault with neither reads its table row's `name` /
    /// `symbol`, and its wrapper `"Wrapped " + name` / `"w" + symbol`; one
    /// with no table row keeps `before`.
    /// @param chainTokens The tokens.
    /// @param before `LibBeaconUpgrade.metadata` before the batch.
    /// @return The expected values.
    function expectedMetadata(TokenInstance[] memory chainTokens, string[] memory before)
        internal
        view
        returns (string[] memory)
    {
        TokenConfig[] memory table = LibProdTokenConfig.canonicalTokenConfigs();
        string[] memory expected = new string[](before.length);
        for (uint256 tokenIndex = 0; tokenIndex < chainTokens.length; tokenIndex++) {
            TokenInstance memory token = chainTokens[tokenIndex];
            LibUnderlyingSnapshot.Lookup memory row =
                LibUnderlyingSnapshot.lookup(UNDERLYING_SNAPSHOT_ROOT, token.receiptVault);
            (bool inTable, TokenConfig memory config) = tableRow(token.underlying, table);
            string memory ticker;
            string memory underlyingName;
            if (row.found) {
                (ticker, underlyingName) = (row.ticker, row.name);
            } else if (inTable && token.receiptVault == LibProdTokenParams.tokenAddress(config)) {
                (ticker, underlyingName) = (config.listingTicker, config.listingName);
            }
            uint256 at = tokenIndex * 4;
            if (bytes(underlyingName).length > 0) {
                expected[at] = LibSecurity.vaultName(underlyingName);
                expected[at + 1] = LibSecurity.vaultSymbol(ticker);
                expected[at + 2] = expected[at];
                expected[at + 3] = string.concat(ticker, "s");
            } else if (inTable) {
                expected[at] = config.name;
                expected[at + 1] = config.symbol;
                expected[at + 2] = string.concat("Wrapped ", config.name);
                expected[at + 3] = string.concat("w", config.symbol);
            } else {
                for (uint256 leg = 0; leg < 4; leg++) {
                    expected[at + leg] = before[at + leg];
                }
            }
        }
        return expected;
    }

    /// @notice The row of `table` for `underlying`, if any.
    /// @param underlying The ticker join key.
    /// @param table The table.
    /// @return Whether there is one, and the row.
    function tableRow(string memory underlying, TokenConfig[] memory table)
        internal
        pure
        returns (bool, TokenConfig memory)
    {
        for (uint256 i = 0; i < table.length; i++) {
            if (keccak256(bytes(table[i].underlying)) == keccak256(bytes(underlying))) return (true, table[i]);
        }
        TokenConfig memory none;
        return (false, none);
    }

    /// @notice Reverts unless `beacon` points at `expected`.
    /// @param beacon The beacon.
    /// @param expected The implementation.
    function assertBeacon(address beacon, address expected) internal view {
        address actual = IBeacon(beacon).implementation();
        if (actual != expected) revert BeaconNotUpgraded(beacon, expected, actual);
    }
}
