// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {LibRainDeploy} from "rain-deploy-0.1.20/src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV3, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.20/src/interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.20/src/lib/LibMigrationRegistryDeploy.sol";

import {
    LibOrchestratorInvariants,
    OrchestratorAdminMissing,
    OrchestratorRoleAdminUnexpected,
    OrchestratorRoleMissing
} from "../../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {BeaconOwnerMismatch} from "../../../src/lib/LibBeaconInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibStoxMigrations} from "../../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibOrchestratorInvariantsHarness} from "./LibOrchestratorInvariantsHarness.sol";
import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";

/// @title LibOrchestratorInvariantsTest
/// @notice The orchestrator invariants against every deployment network at
/// head, then each role invariant driven both ways on a Base fork: the
/// role state a record implies holds, and every disagreement between the
/// record and the role trips its own typed error.
///
/// The scenarios run against a stand-in Safe that has never written to the
/// migration registry and is made the orchestrator's sole admin on the fork
/// (`selectScenarioFork`), so they hold whatever the live chain has already
/// recorded.
contract LibOrchestratorInvariantsTest is Test {
    LibOrchestratorInvariantsHarness internal harness;
    address internal safe;
    address internal timelock;
    bytes32 internal mintRole;
    bytes32 internal burnRole;
    bytes32 internal emergencyRole;
    IAccessControl internal orchestrator = IAccessControl(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);
    IMigrationRegistryV3 internal registry =
        IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);

    function selectFork(string memory network) internal {
        vm.createSelectFork(network);
        harness = new LibOrchestratorInvariantsHarness();
        safe = LibSafeInvariants.safeForChainId(block.chainid);
        timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        mintRole = ST0xOrchestrator(payable(address(orchestrator))).MINT_ROLE();
        burnRole = ST0xOrchestrator(payable(address(orchestrator))).BURN_ROLE();
        emergencyRole = ST0xOrchestrator(payable(address(orchestrator))).EMERGENCY_ROLE();
    }

    /// @notice Fork Base and stand in a fresh Safe: it becomes the sole
    /// `DEFAULT_ADMIN_ROLE` holder, taking it from whichever of the real
    /// Safe and the timelock holds it, and the timelock is cleared of every
    /// operating role, and the stand-in holds `EMERGENCY`, as every chain's Safe
    /// does. This repo's registry line is at genesis.
    function selectScenarioFork() internal {
        selectFork(LibRainDeploy.BASE);
        address realSafe = safe;
        safe = makeAddr("scenario-token-owner-safe");
        address admin = orchestrator.hasRole(bytes32(0), realSafe) ? realSafe : timelock;
        vm.prank(admin);
        orchestrator.grantRole(bytes32(0), safe);
        if (orchestrator.hasRole(bytes32(0), realSafe)) {
            vm.prank(realSafe);
            orchestrator.renounceRole(bytes32(0), realSafe);
        }
        if (orchestrator.hasRole(bytes32(0), timelock)) {
            vm.prank(timelock);
            orchestrator.renounceRole(bytes32(0), timelock);
        }
        bytes32[3] memory roles = [emergencyRole, mintRole, burnRole];
        vm.startPrank(safe);
        for (uint256 i = 0; i < roles.length; i++) {
            orchestrator.revokeRole(roles[i], timelock);
        }
        vm.stopPrank();
        assertEq(LibStoxMigrations.head(), MIGRATION_HEAD_GENESIS, "line not at genesis");
        grantEmergencyToSafe();
    }

    /// @notice Record the chain's migrations up to and including `upTo`, as
    /// the root authority, in line order. Recording only — no role is touched.
    function record(bytes32 upTo) internal {
        vm.prank(LibStoxMigrations.WRITER);
        registry.applyMigrationV3(
            LibStoxMigrations.WRITER, LibStoxMigrations.NAMESPACE, upTo, LibStoxMigrations.onto(MIGRATION_HEAD_GENESIS)
        );
    }

    function grantEmergencyToSafe() internal {
        if (!orchestrator.hasRole(emergencyRole, safe)) {
            vm.prank(safe);
            orchestrator.grantRole(emergencyRole, safe);
        }
    }

    function moveAdminToTimelock() internal {
        vm.startPrank(safe);
        orchestrator.grantRole(bytes32(0), timelock);
        orchestrator.renounceRole(bytes32(0), safe);
        vm.stopPrank();
    }

    /// @notice The invariants hold at head on every network ST0x deploys to.
    function testLiveOnEveryDeploymentNetwork() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            selectFork(networks[i]);
            harness.callAssertBeaconSet();
            harness.callAssertInstance(safe);
        }
    }

    /// @notice The beacon owner must be the chain's timelock exactly; the
    /// Safe that owned it before the governance migration no longer passes.
    function testBeaconOwnedBySafeTrips() external {
        selectFork(LibRainDeploy.BASE);
        vm.mockCall(
            LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON, abi.encodeCall(Ownable.owner, ()), abi.encode(safe)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerMismatch.selector, LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON, timelock, safe
            )
        );
        harness.callAssertBeaconSet();
    }

    /// @notice The Safe holds `EMERGENCY`: passes.
    function testEmergencyGrantedPasses() external {
        selectScenarioFork();
        grantEmergencyToSafe();
        harness.callAssertInstance(safe);
    }

    /// @notice The Safe without `EMERGENCY` trips: the grant ran on every
    /// chain before the line started, so it is always expected.
    function testEmergencyMissingTrips() external {
        selectScenarioFork();
        vm.prank(safe);
        orchestrator.revokeRole(emergencyRole, safe);
        vm.expectRevert(
            abi.encodeWithSelector(OrchestratorRoleMissing.selector, address(orchestrator), emergencyRole, safe)
        );
        harness.callAssertInstance(safe);
    }

    /// @notice Admin moved and recorded: passes.
    function testAdminMovedAndRecordedPasses() external {
        selectScenarioFork();
        grantEmergencyToSafe();
        moveAdminToTimelock();
        record(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        harness.callAssertInstance(safe);
    }

    /// @notice Admin moved without the record: nothing is asserted about
    /// admin until the record lands.
    function testAdminMovedWithoutRecordPasses() external {
        selectScenarioFork();
        grantEmergencyToSafe();
        moveAdminToTimelock();
        harness.callAssertInstance(safe);
    }

    /// @notice Admin recorded as moved while the timelock does not hold it.
    function testAdminRecordedWithoutMoveTrips() external {
        selectScenarioFork();
        grantEmergencyToSafe();
        record(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        vm.expectRevert(abi.encodeWithSelector(OrchestratorAdminMissing.selector, address(orchestrator), timelock));
        harness.callAssertInstance(safe);
    }

    /// @notice Each operating role must be administered by
    /// `DEFAULT_ADMIN_ROLE`; a different admin role changes who decides its
    /// grants, which is the question every check above answers.
    function testRoleAdminChangedTrips() external {
        selectScenarioFork();
        bytes32[4] memory roles = [bytes32(0), mintRole, burnRole, emergencyRole];
        for (uint256 i = 0; i < roles.length; i++) {
            vm.clearMockedCalls();
            vm.mockCall(
                address(orchestrator),
                abi.encodeCall(IAccessControl.getRoleAdmin, (roles[i])),
                abi.encode(keccak256("OTHER_ADMIN"))
            );
            vm.expectRevert(
                abi.encodeWithSelector(
                    OrchestratorRoleAdminUnexpected.selector, address(orchestrator), roles[i], keccak256("OTHER_ADMIN")
                )
            );
            harness.callAssertInstance(safe);
        }
    }

    /// @notice The service signer's `MINT` and `BURN` are expected for the dashboard, not asserted in CI.
    function testServiceSignerMintAndBurnPassHeldOrNot() external {
        selectScenarioFork();
        address signer = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        vm.startPrank(safe);
        orchestrator.grantRole(mintRole, signer);
        orchestrator.grantRole(burnRole, signer);
        vm.stopPrank();
        harness.callAssertInstance(safe);

        vm.startPrank(safe);
        orchestrator.revokeRole(mintRole, signer);
        orchestrator.revokeRole(burnRole, signer);
        vm.stopPrank();
        harness.callAssertInstance(safe);
    }

    /// @notice After the admin move the timelock can revoke the Safe's
    /// `EMERGENCY`, and that trips.
    function testPostMoveDriftTrips() external {
        selectPostMoveScenario();
        vm.prank(timelock);
        orchestrator.revokeRole(emergencyRole, safe);
        vm.expectRevert(
            abi.encodeWithSelector(OrchestratorRoleMissing.selector, address(orchestrator), emergencyRole, safe)
        );
        harness.callAssertInstance(safe);
    }

    /// @notice The stand-in scenario after both stacked migrations: the
    /// stand-in Safe holds `EMERGENCY`, the timelock holds admin, both are
    /// recorded, and the invariant passes.
    function selectPostMoveScenario() internal {
        selectScenarioFork();
        grantEmergencyToSafe();
        moveAdminToTimelock();
        record(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        harness.callAssertInstance(safe);
    }
}
