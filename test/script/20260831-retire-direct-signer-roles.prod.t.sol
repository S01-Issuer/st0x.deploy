// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {LibRainDeploy} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.22/src/lib/LibSafeTx.sol";

import {
    OrchestratorPathNotEnabled,
    TimelockMissingRoleAdminForRetire,
    RetireInsideDelay,
    retireDirectSignerRolesDeclaration
} from "../../script/20260831-retire-direct-signer-roles.s.sol";
import {orchestratorAdminToTimelockDeclaration} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {grantOrchestratorEmergencyDeclaration} from "../../script/20261006-grant-orchestrator-emergency.s.sol";
import {RetireDirectSignerRolesHarness} from "./RetireDirectSignerRolesHarness.sol";
import {LibOrchestratorInvariants, OrchestratorVaultLogicUnexpected} from "../../src/lib/LibOrchestratorInvariants.sol";
import {IST0xOrchestratorV1} from "../../src/interface/deprecated/IST0xOrchestratorV1.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {
    LibStoxMigrations,
    SafeNotApprovedWriter,
    UnexpectedMigrationLine
} from "../../src/lib/LibStoxMigrations.sol";
import {LibMigrationLineFork} from "../lib/LibMigrationLineFork.sol";

contract RetireDirectSignerRolesProdTest is Test {
    address internal constant SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
    bytes32 internal constant RETIRE_SALT = keccak256("st0x.retire-direct-signer-roles.20260831");

    function fork(string memory network, string memory tag) internal returns (RetireDirectSignerRolesHarness) {
        vm.createSelectFork(network);
        LibMigrationLineFork.approve(vm, LibTimelockInvariants.timelockForChainId(block.chainid));
        LibMigrationLineFork.recordOnto(vm, retireDirectSignerRolesDeclaration());
        return new RetireDirectSignerRolesHarness(tag);
    }

    function authoriser() internal view returns (IAccessControl) {
        return IAccessControl(LibAuthoriserInvariants.activeChainAuthoriser());
    }

    function timelock() internal view returns (TimelockController) {
        return TimelockController(payable(LibTimelockInvariants.timelockForChainId(block.chainid)));
    }

    function firstMissingGrant() internal view returns (address, bytes32) {
        IAccessControl acl = authoriser();
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        if (!acl.hasRole(keccak256("DEPOSIT"), orchestrator)) return (orchestrator, keccak256("DEPOSIT"));
        if (!acl.hasRole(keccak256("WITHDRAW"), orchestrator)) return (orchestrator, keccak256("WITHDRAW"));
        if (!IAccessControl(orchestrator).hasRole(keccak256("MINT"), SIGNER)) return (SIGNER, keccak256("MINT"));
        if (!IAccessControl(orchestrator).hasRole(keccak256("BURN"), SIGNER)) return (SIGNER, keccak256("BURN"));
        return (address(0), bytes32(0));
    }

    function revokeDirect(bytes32 role) internal {
        IAccessControl acl = authoriser();
        vm.prank(address(timelock()));
        acl.revokeRole(role, SIGNER);
    }

    function testRetireSchedulesThenExecutesOnEveryNetwork() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            RetireDirectSignerRolesHarness script = fork(networks[i], "rollout");
            (address holder, bytes32 role) = firstMissingGrant();
            if (holder != address(0)) {
                vm.expectRevert(abi.encodeWithSelector(OrchestratorPathNotEnabled.selector, holder, role));
                script.run();
                continue;
            }
            (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
                script.callOperation(address(authoriser()), address(timelock()));
            bytes32 id = timelock().hashOperationBatch(targets, values, payloads, bytes32(0), RETIRE_SALT);

            script.run();
            assertTrue(timelock().isOperationPending(id), networks[i]);
            assertFalse(timelock().isOperationReady(id), networks[i]);
            assertEq(LibStoxMigrations.applied(retireDirectSignerRolesDeclaration().id), 0);

            vm.expectRevert(abi.encodeWithSelector(RetireInsideDelay.selector, id));
            script.run();

            vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
            script.run();
            assertTrue(timelock().isOperationDone(id), networks[i]);
            assertFalse(authoriser().hasRole(keccak256("DEPOSIT"), SIGNER), networks[i]);
            assertFalse(authoriser().hasRole(keccak256("WITHDRAW"), SIGNER), networks[i]);
            assertEq(LibStoxMigrations.applied(retireDirectSignerRolesDeclaration().id), block.timestamp);
            assertEq(LibStoxMigrations.head(), retireDirectSignerRolesDeclaration().id);
        }
    }

    function testOperationIsTheRevokesThenTheRecord() external {
        RetireDirectSignerRolesHarness script = fork(LibRainDeploy.BASE, "operation");
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            script.callOperation(address(authoriser()), address(timelock()));
        assertEq(targets.length, 3);
        assertEq(values.length, 3);
        assertEq(targets[0], address(authoriser()));
        assertEq(payloads[0], abi.encodeCall(IAccessControl.revokeRole, (keccak256("DEPOSIT"), SIGNER)));
        assertEq(targets[1], address(authoriser()));
        assertEq(payloads[1], abi.encodeCall(IAccessControl.revokeRole, (keccak256("WITHDRAW"), SIGNER)));
        (address registry, bytes memory data) = LibStoxMigrations.recordCall(retireDirectSignerRolesDeclaration());
        assertEq(targets[2], registry);
        assertEq(payloads[2], data);
    }

    function testOperationSelfScopesAPartialRetirement() external {
        RetireDirectSignerRolesHarness script = fork(LibRainDeploy.BASE, "partial");
        revokeDirect(keccak256("DEPOSIT"));
        (address[] memory targets,, bytes[] memory payloads) =
            script.callOperation(address(authoriser()), address(timelock()));
        assertEq(targets.length, 2);
        assertEq(payloads[0], abi.encodeCall(IAccessControl.revokeRole, (keccak256("WITHDRAW"), SIGNER)));
    }

    function testRunRecordsOnlyWhereAlreadyRetired() external {
        RetireDirectSignerRolesHarness script = fork(LibRainDeploy.BASE, "retired");
        revokeDirect(keccak256("DEPOSIT"));
        revokeDirect(keccak256("WITHDRAW"));
        (address[] memory targets,,) = script.callOperation(address(authoriser()), address(timelock()));
        assertEq(targets.length, 1);
        script.run();
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        script.run();
        assertEq(LibStoxMigrations.head(), retireDirectSignerRolesDeclaration().id);
    }

    function testOperationRefusesWithoutTimelockRoleAdmin() external {
        RetireDirectSignerRolesHarness script = fork(LibRainDeploy.BASE, "noAdmin");
        IAccessControl acl = authoriser();
        address controller = address(timelock());
        vm.prank(controller);
        acl.renounceRole(keccak256("WITHDRAW_ADMIN"), controller);
        vm.expectRevert(
            abi.encodeWithSelector(TimelockMissingRoleAdminForRetire.selector, keccak256("WITHDRAW_ADMIN"))
        );
        script.callOperation(address(acl), controller);
    }

    function testRunRefusesAnUnapprovedTimelock() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        LibMigrationLineFork.recordOnto(vm, retireDirectSignerRolesDeclaration());
        RetireDirectSignerRolesHarness script = new RetireDirectSignerRolesHarness("unapproved");
        vm.expectRevert(abi.encodeWithSelector(SafeNotApprovedWriter.selector, address(timelock())));
        script.run();
    }

    function testRunRefusesBeforeTheAdminMoveIsRecorded() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        LibMigrationLineFork.approve(vm, address(timelock()));
        LibMigrationLineFork.recordOnto(vm, orchestratorAdminToTimelockDeclaration());
        RetireDirectSignerRolesHarness script = new RetireDirectSignerRolesHarness("early");
        vm.expectRevert(
            abi.encodeWithSelector(UnexpectedMigrationLine.selector, grantOrchestratorEmergencyDeclaration().id)
        );
        script.run();
    }

    function testVerifyAcceptsTheScheduleArtifact() external {
        RetireDirectSignerRolesHarness script = fork(LibRainDeploy.BASE, "verify");
        uint256 preRun = vm.snapshotState();
        script.run();
        string memory path = script.callArtifactPath();
        vm.revertToState(preRun);
        script.verify(path);
        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, 1);
        assertEq(txs[0].to, address(timelock()));
        assertEq(bytes4(txs[0].data), TimelockController.scheduleBatch.selector);
    }

    function testRunRefusesOrchestratorInstanceOffInvariant() external {
        RetireDirectSignerRolesHarness script = fork(LibRainDeploy.BASE, "offInvariant");
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        vm.mockCall(orchestrator, abi.encodeCall(IST0xOrchestratorV1.vaultLogicIsExpected, ()), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(OrchestratorVaultLogicUnexpected.selector, orchestrator));
        script.run();
    }

    function testVerifyRefusesOrchestratorInstanceOffInvariant() external {
        RetireDirectSignerRolesHarness script = fork(LibRainDeploy.BASE, "offInvariantVerify");
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        vm.mockCall(orchestrator, abi.encodeCall(IST0xOrchestratorV1.vaultLogicIsExpected, ()), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(OrchestratorVaultLogicUnexpected.selector, orchestrator));
        script.verify("missing-artifact.json");
    }
}
