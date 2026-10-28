// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.25/src/interface/IMigrationRegistryV3.sol";
import {SafeTx} from "rain-deploy-0.1.25/src/lib/LibSafeTx.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.25/src/lib/LibSafeTxBuilderJson.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.25/src/lib/LibMigrationRegistry.sol";
import {LibSafe} from "rain-deploy-0.1.25/src/lib/LibSafe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.25/src/lib/LibRainDeploy.sol";

import {migrateMultisigThresholdDeclaration} from "../../script/20260619-migrate-multisig-threshold.s.sol";
import {MigrateMultisigThresholdHarness} from "./MigrateMultisigThresholdHarness.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {
    LibStoxMigrations,
    RecordMismatch,
    SafeNotApprovedWriter,
    UnexpectedMigrationLine
} from "../../src/lib/LibStoxMigrations.sol";
import {LibMigrationLineFork} from "../lib/LibMigrationLineFork.sol";

contract MigrateMultisigThresholdTest is Test {
    bytes32 internal constant ID = keccak256("script/20260619-migrate-multisig-threshold.s.sol");

    function fork(string memory network, string memory tag) internal returns (MigrateMultisigThresholdHarness, Safe) {
        vm.createSelectFork(network);
        Safe safe = Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
        LibMigrationLineFork.approve(vm, address(safe));
        return (new MigrateMultisigThresholdHarness(tag), safe);
    }

    /// @notice `fork`, or the zero harness when the threshold is already
    /// recorded on the chain and the line is past the state these tests need.
    function pendingFork(string memory network, string memory tag)
        internal
        returns (MigrateMultisigThresholdHarness, Safe)
    {
        (MigrateMultisigThresholdHarness script, Safe safe) = fork(network, tag);
        if (LibStoxMigrations.applied(ID) != 0) {
            console2.log(string.concat("SPENT [", network, "]: the threshold is recorded on this chain"));
            return (MigrateMultisigThresholdHarness(address(0)), safe);
        }
        return (script, safe);
    }

    function testDeclarationIsTheLineRoot() external pure {
        assertEq(migrateMultisigThresholdDeclaration().id, ID);
        assertEq(migrateMultisigThresholdDeclaration().onto, MIGRATION_HEAD_GENESIS);
    }

    /// @notice On a Safe at the pin, the threshold runs as the record alone,
    /// or, where it is already recorded, refuses to record again.
    function assertRecordsOnlyAtThePin(string memory network, MigrateMultisigThresholdHarness script, Safe safe)
        internal
    {
        assertEq(safe.getThreshold(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
        if (LibStoxMigrations.applied(ID) != 0) {
            console2.log(string.concat("RECORDED [", network, "]: asserting the live record"));
            assertEq(
                LibMigrationRegistry.appliedOntoV3(LibStoxMigrations.WRITER, LibStoxMigrations.NAMESPACE, ID),
                MIGRATION_HEAD_GENESIS
            );
            // Selector only: a later recorded migration moves the head.
            vm.expectPartialRevert(UnexpectedMigrationLine.selector);
            script.run();
            return;
        }
        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, 1);
        (address registry, bytes memory data) = LibStoxMigrations.recordCall(migrateMultisigThresholdDeclaration());
        assertEq(txs[0].to, registry);
        assertEq(txs[0].data, data);
        script.run();
        assertEq(LibStoxMigrations.applied(ID), block.timestamp);
        assertEq(LibStoxMigrations.head(), ID);
        assertEq(safe.getThreshold(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
    }

    function testRunRecordsOnlyOnEveryNetworkAtThePin() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            (MigrateMultisigThresholdHarness script, Safe safe) = fork(networks[i], "recordOnly");
            assertRecordsOnlyAtThePin(networks[i], script, safe);
        }
    }

    /// @notice Where the threshold is already recorded, the pin check takes
    /// its recorded branch.
    function testRunRefusesWhereTheThresholdIsRecorded() external {
        (MigrateMultisigThresholdHarness script, Safe safe) = fork(LibRainDeploy.BASE, "recorded");
        if (LibStoxMigrations.applied(ID) == 0) script.run();
        assertTrue(LibStoxMigrations.applied(ID) != 0);
        assertRecordsOnlyAtThePin(LibRainDeploy.BASE, new MigrateMultisigThresholdHarness("recordedAgain"), safe);
    }

    function testRunRaisesTheThresholdWhenBelowThePin() external {
        (MigrateMultisigThresholdHarness script, Safe safe) = pendingFork(LibRainDeploy.BASE, "raise");
        if (address(script) == address(0)) return;
        vm.prank(address(safe));
        safe.changeThreshold(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_CREATION_THRESHOLD);
        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, 2);
        assertEq(txs[0].to, address(safe));
        assertEq(
            txs[0].data,
            abi.encodeCall(OwnerManager.changeThreshold, (LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD))
        );
        script.run();
        assertEq(safe.getThreshold(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
        assertEq(LibStoxMigrations.head(), ID);
    }

    function testRunRefusesAnUnapprovedSafe() external {
        (MigrateMultisigThresholdHarness script, Safe safe) = pendingFork(LibRainDeploy.BASE, "unapproved");
        if (address(script) == address(0)) return;
        LibMigrationLineFork.revoke(vm, address(safe));
        vm.expectRevert(abi.encodeWithSelector(SafeNotApprovedWriter.selector, address(safe)));
        script.run();
    }

    function testRunRefusesALineAlreadyPastGenesis() external {
        (MigrateMultisigThresholdHarness script,) = pendingFork(LibRainDeploy.BASE, "twice");
        if (address(script) == address(0)) return;
        script.run();
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, ID));
        script.run();
    }

    function testRunRefusesOwnerDrift() external {
        (MigrateMultisigThresholdHarness script, Safe safe) = pendingFork(LibRainDeploy.BASE, "ownerDrift");
        if (address(script) == address(0)) return;
        address[] memory owners = safe.getOwners();
        vm.prank(address(safe));
        safe.swapOwner(address(1), owners[0], address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(LibSafe.SafeUnexpectedOwner.selector, address(safe), address(0xBEEF)));
        script.run();
    }

    function testVerifyAcceptsTheRunArtifactAndRejectsTamper() external {
        (MigrateMultisigThresholdHarness script, Safe safe) = pendingFork(LibRainDeploy.BASE, "verify");
        if (address(script) == address(0)) return;
        uint256 preRun = vm.snapshotState();
        script.run();
        string memory path = script.callArtifactPath();
        vm.revertToState(preRun);
        script.verify(path);

        (,, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(path));
        txs[0].data = abi.encodeCall(OwnerManager.changeThreshold, (uint256(4)));
        string memory tampered = string.concat(path, ".tampered.json");
        vm.writeFile(tampered, LibSafeTxBuilderJson.toJson(vm, address(safe), block.chainid, "tampered", txs));
        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.ArtifactMismatch.selector, "data"));
        script.verify(tampered);
    }

    function testPostStateRefusesAMissingRecord() external {
        (MigrateMultisigThresholdHarness script,) = pendingFork(LibRainDeploy.BASE, "unrecorded");
        if (address(script) == address(0)) return;
        vm.expectRevert(abi.encodeWithSelector(RecordMismatch.selector, ID, block.timestamp, 0));
        script.callAssertPostState();
        script.run();
        script.callAssertPostState();
    }
}
