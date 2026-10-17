// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistryDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.18/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.18/src/lib/LibSafeFork.sol";
import {LibSafe} from "rain-deploy-0.1.18/src/lib/LibSafe.sol";
import {IMigrationRegistryV2} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.18/src/lib/LibSafeTxBuilderJson.sol";

import {
    ThresholdLineHeadMismatch,
    UnexpectedThresholdMigrationLine,
    migrateMultisigThresholdDeclaration
} from "../../script/MigrateMultisigThreshold.s.sol";
import {GrantOrchestratorEmergencyHarness} from "./GrantOrchestratorEmergencyHarness.sol";
import {MigrateMultisigThresholdHarness} from "./MigrateMultisigThresholdHarness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

contract MigrateMultisigThresholdTest is Test {
    function threshold() internal pure returns (bytes32) {
        return keccak256("script/MigrateMultisigThreshold.s.sol");
    }

    /// @dev Executes the two bundles the threshold record is applied after,
    /// where the chain has not.
    function executePrerequisites(string memory network, address safe) internal {
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) == 0) {
            GrantOrchestratorEmergencyHarness grant = new GrantOrchestratorEmergencyHarness(network);
            LibSafeFork.executeBundle(vm, Safe(payable(safe)), grant.callAuthorBundle());
        }
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) == 0) {
            OrchestratorAdminToTimelockHarness admin = new OrchestratorAdminToTimelockHarness(network);
            LibSafeFork.executeBundle(vm, Safe(payable(safe)), admin.callAuthorBundle());
        }
    }

    function assertBundle(string memory network) internal {
        vm.createSelectFork(network);
        MigrateMultisigThresholdHarness script = new MigrateMultisigThresholdHarness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);

        if (LibStoxMigrations.applied(safe, threshold()) != 0) {
            vm.expectPartialRevert(UnexpectedThresholdMigrationLine.selector);
            script.callPreflight();
            return;
        }

        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) == 0) {
            vm.expectRevert(
                abi.encodeWithSelector(UnexpectedThresholdMigrationLine.selector, LibStoxMigrations.head(safe))
            );
            script.callPreflight();
            executePrerequisites(network, safe);
        }

        uint256 preRun = vm.snapshotState();
        script.run();
        vm.revertToState(preRun);

        string memory artifactPath = script.callArtifactPath();
        script.verify(artifactPath);
        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, safe, "artifact Safe");
        assertEq(txs.length, 1, "the record alone");
        assertEq(txs[0].to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, "to the registry");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        assertEq(LibStoxMigrations.applied(safe, threshold()), block.timestamp, "record stamped when it lands");
        assertEq(LibStoxMigrations.head(safe), threshold(), "line ends at the record");
        LibSafeInvariants.assertTokenOwnerSafePolicy(Safe(payable(safe)));
        vm.expectRevert(abi.encodeWithSelector(UnexpectedThresholdMigrationLine.selector, threshold()));
        script.callPreflight();
    }

    function testDeclarationIsTheScriptPathOntoTheAdminMove() external pure {
        assertEq(migrateMultisigThresholdDeclaration().id, threshold());
        assertEq(migrateMultisigThresholdDeclaration().namespace, LibStoxMigrations.NAMESPACE);
        assertEq(
            migrateMultisigThresholdDeclaration().prerequisites[0].migration,
            LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK
        );
    }

    function testRefusesASafeOffItsPolicyThreshold() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        MigrateMultisigThresholdHarness script = new MigrateMultisigThresholdHarness("off-policy");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        vm.prank(safe);
        Safe(payable(safe)).changeThreshold(2);
        vm.expectRevert(abi.encodeWithSelector(LibSafe.SafeThresholdMismatch.selector, safe, 3, 2));
        script.callPreflight();
    }

    function testRunRefusesALineThatDoesNotEndAtTheRecord() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        MigrateMultisigThresholdHarness script = new MigrateMultisigThresholdHarness("head-mismatch");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        executePrerequisites("head-mismatch", safe);
        vm.mockCall(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            abi.encodeCall(IMigrationRegistryV2.head, (safe, LibStoxMigrations.NAMESPACE)),
            abi.encode(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK)
        );
        vm.expectRevert(
            abi.encodeWithSelector(ThresholdLineHeadMismatch.selector, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK)
        );
        script.run();
    }

    function testRecordBase() external {
        assertBundle(LibRainDeploy.BASE);
    }

    function testRecordEthereum() external {
        assertBundle(LibStoxDeployNetworks.ETHEREUM);
    }

    function testRecordHyperEvm() external {
        assertBundle(LibStoxDeployNetworks.HYPEREVM);
    }

    function testRecordRobinhood() external {
        assertBundle(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testRecordBsc() external {
        assertBundle(LibStoxDeployNetworks.BSC);
    }
}
