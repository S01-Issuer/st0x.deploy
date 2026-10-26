// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.22/src/interface/IMigrationRegistryV3.sol";
import {SafeTx} from "rain-deploy-0.1.22/src/lib/LibSafeTx.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.22/src/lib/LibSafeTxBuilderJson.sol";
import {LibSafe} from "rain-deploy-0.1.22/src/lib/LibSafe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";

import {migrateMultisigThresholdDeclaration} from "../../script/20260619-migrate-multisig-threshold.s.sol";
import {MigrateMultisigThresholdHarness} from "./MigrateMultisigThresholdHarness.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations, SafeNotApprovedWriter, UnexpectedMigrationLine} from "../../src/lib/LibStoxMigrations.sol";
import {LibMigrationLineFork} from "../lib/LibMigrationLineFork.sol";

contract MigrateMultisigThresholdTest is Test {
    bytes32 internal constant ID = keccak256("script/20260619-migrate-multisig-threshold.s.sol");

    function fork(string memory network, string memory tag) internal returns (MigrateMultisigThresholdHarness, Safe) {
        vm.createSelectFork(network);
        Safe safe = Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
        LibMigrationLineFork.approve(vm, address(safe));
        return (new MigrateMultisigThresholdHarness(tag), safe);
    }

    function testDeclarationIsTheLineRoot() external pure {
        assertEq(migrateMultisigThresholdDeclaration().id, ID);
        assertEq(migrateMultisigThresholdDeclaration().onto, MIGRATION_HEAD_GENESIS);
    }

    function testRunRecordsOnlyOnEveryNetworkAtThePin() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            (MigrateMultisigThresholdHarness script, Safe safe) = fork(networks[i], "recordOnly");
            assertEq(safe.getThreshold(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
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
    }

    function testRunRaisesTheThresholdWhenBelowThePin() external {
        (MigrateMultisigThresholdHarness script, Safe safe) = fork(LibRainDeploy.BASE, "raise");
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
        vm.createSelectFork(LibRainDeploy.BASE);
        MigrateMultisigThresholdHarness script = new MigrateMultisigThresholdHarness("unapproved");
        vm.expectRevert(
            abi.encodeWithSelector(SafeNotApprovedWriter.selector, LibSafeInvariants.safeForChainId(block.chainid))
        );
        script.run();
    }

    function testRunRefusesALineAlreadyPastGenesis() external {
        (MigrateMultisigThresholdHarness script,) = fork(LibRainDeploy.BASE, "twice");
        script.run();
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, ID));
        script.run();
    }

    function testRunRefusesOwnerDrift() external {
        (MigrateMultisigThresholdHarness script, Safe safe) = fork(LibRainDeploy.BASE, "ownerDrift");
        address[] memory owners = safe.getOwners();
        vm.prank(address(safe));
        safe.swapOwner(address(1), owners[0], address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(LibSafe.SafeUnexpectedOwner.selector, address(safe), address(0xBEEF)));
        script.run();
    }

    function testVerifyAcceptsTheRunArtifactAndRejectsTamper() external {
        (MigrateMultisigThresholdHarness script, Safe safe) = fork(LibRainDeploy.BASE, "verify");
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
}
