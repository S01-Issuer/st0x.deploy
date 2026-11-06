// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {
    MigrateMultisigThreshold,
    VerifyMismatch,
    VerifyExpectedSingleTx,
    MultisigThresholdAlreadyApplied
} from "../../script/20260619-migrate-multisig-threshold.s.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.30/src/lib/LibSafeTxBuilderJson.sol";
import {LibSafe} from "rain-deploy-0.1.30/src/lib/LibSafe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";

/// @title MigrateMultisigThresholdTest
/// @notice End-to-end fork tests for the multisig threshold migration
/// script. Covers the happy-path `run()` dry-run, inverted preconditions
/// (each pre-flight invariant is exercised by mocking a single drift in
/// isolation), and the `run()` -> `verify()` chain (i.e. `verify` accepts
/// what `run` emits).
contract MigrateMultisigThresholdTest is Test {
    /// @notice The script under test, deployed fresh per fork.
    MigrateMultisigThreshold internal script;

    /// @notice Live Safe handle.
    Safe internal safe;

    /// @notice Selects Base at its pinned pre-backfill block, where the
    /// threshold migration is not yet recorded.
    function selectBaseFork() internal {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        script = new MigrateMultisigThreshold();
        safe = Safe(payable(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE));
    }

    /// @notice `run()` dry-run completes against the live pre-state,
    /// writes the artifact, and the artifact has the expected single-tx
    /// shape. The final fork state must show the threshold back at the
    /// pinned pre-migration value — this is the n+1 reversibility check's
    /// observable side effect: the script ends with the safe rolled back,
    /// proving the new state is exitable.
    function testRunCompletesAndWritesArtifact() external {
        selectBaseFork();
        script.run();

        // The artifact path the script writes to is project-relative,
        // resolved against `vm.projectRoot()`.
        string memory artifactPath = string.concat(vm.projectRoot(), "/out/safe-threshold-migration.json");
        string memory json = vm.readFile(artifactPath);

        // Smoke-check the JSON shape.
        string memory bundleName = vm.parseJsonString(json, ".meta.name");
        assertEq(bundleName, "ST0x Safe threshold 1->3 (post-rotation roster)", "meta.name pinned");
        bool hasFirstTx = vm.keyExistsJson(json, ".transactions[0].to");
        bool hasSecondTx = vm.keyExistsJson(json, ".transactions[1].to");
        assertTrue(hasFirstTx, "first transaction present");
        assertFalse(hasSecondTx, "exactly one transaction emitted");

        // After `run()` the n+1 reversibility check has rolled the
        // threshold back to its pre-migration value. Asserting the final
        // fork state matches the pinned pre-migration threshold is the
        // observable evidence that the reversal path executed
        // successfully — without it we'd be relying solely on the absence
        // of an internal revert.
        assertEq(
            safe.getThreshold(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
            "n+1 reversibility check rolled threshold back to pre-migration value"
        );
    }

    /// @notice `verify()` accepts the artifact emitted by `run()`. This
    /// is the load-bearing round-trip property — a signer should be able
    /// to take the artifact, run `verify` against the same fork, and get
    /// silent success.
    function testVerifyAcceptsRunArtifact() external {
        selectBaseFork();
        // `run()` simulates the inner call via `vm.prank`, which mutates
        // the Safe's threshold on the active fork. Snapshot first so we
        // can roll the fork back to the pre-run state and `verify()` sees
        // the same pinned current threshold it would see in production.
        uint256 snapshot = vm.snapshotState();
        script.run();
        string memory artifactPath = string.concat(vm.projectRoot(), "/out/safe-threshold-migration.json");
        vm.revertToState(snapshot);
        script.verify(artifactPath);
    }

    /// @notice Inverted: the pre-flight rejects a drifted threshold. If the
    /// Safe's threshold has moved off the pinned current value (3), `run()`
    /// must trip the threshold invariant rather than emitting a stale
    /// artifact.
    function testRunRejectsThresholdDrift() external {
        selectBaseFork();
        // Mock the Safe's threshold away from the pinned current value (3)
        // to simulate drift; the pre-flight rejects before producing an
        // artifact.
        vm.mockCall(address(safe), abi.encodeCall(OwnerManager.getThreshold, ()), abi.encode(uint256(1)));

        vm.expectRevert(
            abi.encodeWithSelector(LibSafe.SafeThresholdMismatch.selector, address(safe), uint256(3), uint256(1))
        );
        script.run();
    }

    /// @notice Inverted: `verify()` names the field an artifact gets wrong:
    /// its chain id, the Safe it targets, or the threshold its calldata sets.
    function testVerifyRejectsAWrongField() external {
        selectBaseFork();
        address impostor = address(0xCAFEBABE);
        address[3] memory safes = [address(safe), impostor, address(safe)];
        uint256[3] memory chainIds = [block.chainid + 1, block.chainid, block.chainid];
        uint256[3] memory thresholds = [uint256(3), 3, 4];
        string[3] memory fields = ["chainId", "safeAddress", "data"];
        for (uint256 i = 0; i < fields.length; i++) {
            SafeTx[] memory txs = new SafeTx[](1);
            txs[0] = SafeTx({
                to: safes[i],
                value: 0,
                data: abi.encodeCall(OwnerManager.changeThreshold, (thresholds[i])),
                operation: Enum.Operation.Call
            });
            string memory path = string.concat(vm.projectRoot(), "/out/safe-verify-wrong-", fields[i], ".json");
            vm.writeFile(path, LibSafeTxBuilderJson.toJson(vm, safes[i], chainIds[i], fields[i], txs));
            vm.expectRevert(abi.encodeWithSelector(VerifyMismatch.selector, fields[i]));
            script.verify(path);
        }
    }

    function chains() internal pure returns (uint256[5] memory) {
        return [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
    }

    function testHistoryAtExecutedAtOpensTheRootLine(uint256 index) external {
        uint256 chainId = chains()[bound(index, 0, 4)];
        MigrateMultisigThreshold migration = new MigrateMultisigThreshold();
        uint256 executedAt = migration.executedAt(chainId);
        address writer = LibSafeInvariants.safeForChainId(chainId);
        LibTestRootLine.etchRegistry(vm);
        LibTestRootLine.approve(vm, writer);
        vm.warp(executedAt + 1 days);

        (address to, bytes memory data) = LibStoxMigrations.historyCall(migration.declaration(chainId), executedAt);
        vm.prank(writer);
        (bool ok,) = to.call(data);
        assertTrue(ok);

        assertEq(LibStoxMigrations.applied(LibStoxMigrations.MULTISIG_THRESHOLD), executedAt);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.MULTISIG_THRESHOLD);
    }

    function assertThresholdChangedAt(
        MigrateMultisigThreshold migration,
        string memory network,
        uint256 chainId,
        uint256 blockNumber
    ) internal {
        // A fork at the change's block reads its header and logs; no state at
        // that block is touched, so no archive node is needed.
        vm.createSelectFork(network, blockNumber);
        assertEq(block.chainid, chainId, network);

        bytes32[] memory topics = new bytes32[](1);
        topics[0] = keccak256("ChangedThreshold(uint256)");
        Vm.EthGetLogs[] memory logs =
            vm.eth_getLogs(blockNumber, blockNumber, LibSafeInvariants.safeForChainId(chainId), topics);
        assertEq(logs.length, 1, string.concat(network, ": the Safe changes its threshold in the block"));
        assertEq(logs[0].data, abi.encode(uint256(3)), string.concat(network, ": to 3"));
        assertEq(migration.executedAt(chainId), block.timestamp, string.concat(network, ": executedAt"));
    }

    function testExecutedAtIsTheThresholdChangeBlockOnEveryChain() external {
        MigrateMultisigThreshold migration = new MigrateMultisigThreshold();
        vm.makePersistent(address(migration));
        assertThresholdChangedAt(migration, LibRainDeploy.BASE, LibSafeInvariants.BASE_CHAIN_ID, 47725937);
        assertThresholdChangedAt(migration, LibRainDeploy.ETHEREUM, LibSafeInvariants.ETHEREUM_CHAIN_ID, 25552949);
        assertThresholdChangedAt(migration, LibRainDeploy.HYPEREVM, LibSafeInvariants.HYPEREVM_CHAIN_ID, 41323887);
        assertThresholdChangedAt(migration, LibRainDeploy.ROBINHOOD, LibSafeInvariants.ROBINHOOD_CHAIN_ID, 59658260);
        assertThresholdChangedAt(migration, LibRainDeploy.BSC, LibSafeInvariants.BSC_CHAIN_ID, 121126994);
    }

    function testRunRefusesWhenAlreadyRecorded() external {
        address writer = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        LibTestRootLine.etchRegistry(vm);
        LibTestRootLine.approve(vm, writer);
        LibTestRootLine.write(vm, writer, LibStoxMigrations.MULTISIG_THRESHOLD, MIGRATION_HEAD_GENESIS);

        MigrateMultisigThreshold migration = new MigrateMultisigThreshold();
        vm.expectRevert(MultisigThresholdAlreadyApplied.selector);
        migration.run();
    }
}
