// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistryDeploy.sol";
import {IMigrationRegistryV2, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {SafeTx} from "rain-deploy-0.1.18/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.18/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.18/src/lib/LibSafeTxBuilderJson.sol";

import {
    DirectSignerRoleAlreadyRetired,
    OrchestratorPathNotEnabled,
    RetirementAlreadyScheduled,
    UnexpectedRetireMigrationLine,
    retireDirectSignerRolesDeclaration
} from "../../script/20260831-retire-direct-signer-roles.s.sol";
import {MigrationWriter} from "../../src/interface/IStoxScript.sol";
import {RetireDirectSignerRolesHarness} from "./RetireDirectSignerRolesHarness.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibRbacMigration} from "../../src/lib/LibRbacMigration.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

contract RetireDirectSignerRolesTest is Test {
    address internal constant SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

    function assertRetirement(string memory network) internal {
        vm.createSelectFork(network);
        RetireDirectSignerRolesHarness script = new RetireDirectSignerRolesHarness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        IAccessControl acl = IAccessControl(LibAuthoriserInvariants.authoriserForChainId(block.chainid));

        if (!acl.hasRole(keccak256("DEPOSIT"), SIGNER)) {
            vm.expectRevert(abi.encodeWithSelector(DirectSignerRoleAlreadyRetired.selector, keccak256("DEPOSIT")));
            script.callPreflight();
            return;
        }

        uint256 preRun = vm.snapshotState();
        script.run();
        vm.revertToState(preRun);

        string memory artifactPath = script.callArtifactPath();
        script.verify(artifactPath);
        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, safe, "artifact Safe");
        assertEq(txs.length, 1, "one schedule");
        assertEq(txs[0].to, timelock, "to the timelock");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        bytes32 id = script.callOperationId();
        TimelockController controller = TimelockController(payable(timelock));
        assertTrue(controller.isOperationPending(id), "scheduled");
        assertFalse(controller.isOperationReady(id), "not ready inside the delay");
        vm.expectRevert(abi.encodeWithSelector(RetirementAlreadyScheduled.selector, id));
        script.callPreflight();

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = script.callBatch();
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.prank(address(0xbeef));
        controller.executeBatch(
            targets, values, payloads, bytes32(0), keccak256("st0x.rbac.service-signer.direct-roles-retired")
        );

        assertFalse(acl.hasRole(keccak256("DEPOSIT"), SIGNER), "DEPOSIT retired");
        assertFalse(acl.hasRole(keccak256("WITHDRAW"), SIGNER), "WITHDRAW retired");
        assertTrue(acl.hasRole(keccak256("CERTIFY"), SIGNER), "CERTIFY kept");
        assertEq(
            LibMigrationRegistry.applied(
                timelock, LibRbacMigration.STOX_RBAC_NAMESPACE, LibRbacMigration.SERVICE_SIGNER_DIRECT_ROLES_RETIRED
            ),
            block.timestamp,
            "record under the timelock, stamped when it landed"
        );
        assertEq(
            LibMigrationRegistry.head(timelock, LibRbacMigration.STOX_RBAC_NAMESPACE),
            LibRbacMigration.SERVICE_SIGNER_DIRECT_ROLES_RETIRED,
            "the timelock's line ends at the record"
        );
    }

    function testDeclarationIsTheTimelocksFirstRbacRecord() external pure {
        assertEq(retireDirectSignerRolesDeclaration().namespace, LibRbacMigration.STOX_RBAC_NAMESPACE);
        assertEq(retireDirectSignerRolesDeclaration().id, LibRbacMigration.SERVICE_SIGNER_DIRECT_ROLES_RETIRED);
        assertEq(uint256(retireDirectSignerRolesDeclaration().writer), uint256(MigrationWriter.Timelock));
        assertEq(
            uint256(retireDirectSignerRolesDeclaration().prerequisites[0].writer), uint256(MigrationWriter.Timelock)
        );
    }

    function guardFork(string memory tag)
        internal
        returns (RetireDirectSignerRolesHarness script, address timelock, IAccessControl acl)
    {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        script = new RetireDirectSignerRolesHarness(tag);
        timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        acl = IAccessControl(LibAuthoriserInvariants.authoriserForChainId(block.chainid));
    }

    function testRefusesASignerAlreadyRetired() external {
        (RetireDirectSignerRolesHarness script, address timelock, IAccessControl acl) = guardFork("already-retired");
        vm.prank(timelock);
        acl.revokeRole(keccak256("DEPOSIT"), SIGNER);
        vm.expectRevert(abi.encodeWithSelector(DirectSignerRoleAlreadyRetired.selector, keccak256("DEPOSIT")));
        script.callPreflight();
    }

    function testRefusesATimelockLineOffGenesis() external {
        (RetireDirectSignerRolesHarness script, address timelock,) = guardFork("line-moved");
        vm.prank(timelock);
        IMigrationRegistryV2(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigration(
                LibRbacMigration.STOX_RBAC_NAMESPACE,
                keccak256("another"),
                LibMigrationRegistry.onto(timelock, LibRbacMigration.STOX_RBAC_NAMESPACE, MIGRATION_HEAD_GENESIS)
            );
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRetireMigrationLine.selector, keccak256("another")));
        script.callPreflight();
    }

    function testRefusesWhileTheOrchestratorCannotDeposit() external {
        (RetireDirectSignerRolesHarness script, address timelock, IAccessControl acl) = guardFork("path-off");
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        vm.prank(timelock);
        acl.revokeRole(keccak256("DEPOSIT"), orchestrator);
        vm.expectRevert(abi.encodeWithSelector(OrchestratorPathNotEnabled.selector, orchestrator, keccak256("DEPOSIT")));
        script.callPreflight();
    }

    function testRetirementBase() external {
        assertRetirement(LibRainDeploy.BASE);
    }

    function testRetirementEthereum() external {
        assertRetirement(LibStoxDeployNetworks.ETHEREUM);
    }

    function testRetirementHyperEvm() external {
        assertRetirement(LibStoxDeployNetworks.HYPEREVM);
    }

    function testRetirementRobinhood() external {
        assertRetirement(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testRetirementBsc() external {
        assertRetirement(LibStoxDeployNetworks.BSC);
    }
}
