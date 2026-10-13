// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {LibRainDeploy} from "rain-deploy-0.1.17/src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV2, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.17/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.17/src/lib/LibMigrationRegistryDeploy.sol";

import {
    LibOrchestratorInvariants,
    OrchestratorAdminMissing,
    OrchestratorRoleAdminUnexpected,
    OrchestratorRoleMissing,
    OrchestratorUnexpectedRoleHolder
} from "../../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {BeaconOwnerMismatch} from "../../../src/lib/LibBeaconInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
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
    IMigrationRegistryV2 internal registry =
        IMigrationRegistryV2(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);

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
    /// operating role. The stand-in's registry line is at genesis.
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
        assertEq(LibStoxMigrations.head(safe), MIGRATION_HEAD_GENESIS, "stand-in line not at genesis");
    }

    /// @notice Record the chain's migrations up to and including `upTo`, as
    /// the Safe, in line order. Recording only — no role is touched.
    function record(bytes32 upTo) internal {
        (uint256 executedAt,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);
        vm.startPrank(safe);
        if (LibStoxMigrations.head(safe) == MIGRATION_HEAD_GENESIS) {
            registry.applyMigrationHistory(
                LibStoxMigrations.NAMESPACE,
                LibStoxMigrations.GOVERNANCE_TIMELOCK,
                executedAt,
                LibStoxMigrations.onto(safe, MIGRATION_HEAD_GENESIS)
            );
        }
        if (
            upTo != LibStoxMigrations.GOVERNANCE_TIMELOCK
                && LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) == 0
        ) {
            registry.applyMigration(
                LibStoxMigrations.NAMESPACE,
                LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
                LibStoxMigrations.onto(safe, LibStoxMigrations.GOVERNANCE_TIMELOCK)
            );
        }
        if (upTo == LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) {
            registry.applyMigration(
                LibStoxMigrations.NAMESPACE,
                LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
                LibStoxMigrations.onto(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY)
            );
        }
        vm.stopPrank();
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

    /// @notice Granted and recorded: passes.
    function testEmergencyGrantedAndRecordedPasses() external {
        selectScenarioFork();
        grantEmergencyToSafe();
        record(LibStoxMigrations.ORCHESTRATOR_EMERGENCY);
        harness.callAssertInstance(safe);
    }

    /// @notice Granted without the record: the grant landed outside a
    /// recorded migration, which is what a hand-built transaction does.
    function testEmergencyGrantedWithoutRecordTrips() external {
        selectScenarioFork();
        grantEmergencyToSafe();
        vm.expectRevert(
            abi.encodeWithSelector(
                OrchestratorUnexpectedRoleHolder.selector, address(orchestrator), emergencyRole, safe
            )
        );
        harness.callAssertInstance(safe);
    }

    /// @notice Recorded without the grant: the record says a migration ran
    /// that did not.
    function testEmergencyRecordedWithoutGrantTrips() external {
        selectScenarioFork();
        record(LibStoxMigrations.ORCHESTRATOR_EMERGENCY);
        vm.expectRevert(
            abi.encodeWithSelector(OrchestratorRoleMissing.selector, address(orchestrator), emergencyRole, safe)
        );
        harness.callAssertInstance(safe);
    }

    /// @notice The timelock never holds `EMERGENCY_ROLE`, recorded or not.
    function testTimelockHoldingEmergencyTrips() external {
        selectScenarioFork();
        grantEmergencyToSafe();
        record(LibStoxMigrations.ORCHESTRATOR_EMERGENCY);
        vm.prank(safe);
        orchestrator.grantRole(emergencyRole, timelock);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrchestratorUnexpectedRoleHolder.selector, address(orchestrator), emergencyRole, timelock
            )
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

    /// @notice Admin moved without the record: the Safe is expected as
    /// admin and is not.
    function testAdminMovedWithoutRecordTrips() external {
        selectScenarioFork();
        grantEmergencyToSafe();
        record(LibStoxMigrations.ORCHESTRATOR_EMERGENCY);
        moveAdminToTimelock();
        vm.expectRevert(abi.encodeWithSelector(OrchestratorAdminMissing.selector, address(orchestrator), safe));
        harness.callAssertInstance(safe);
    }

    /// @notice Admin recorded as moved while the Safe still holds it.
    function testAdminRecordedWithoutMoveTrips() external {
        selectScenarioFork();
        grantEmergencyToSafe();
        record(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        vm.expectRevert(abi.encodeWithSelector(OrchestratorAdminMissing.selector, address(orchestrator), timelock));
        harness.callAssertInstance(safe);
    }

    /// @notice Admin granted to the timelock but never renounced by the
    /// Safe: the Safe keeps a direct, untimelocked path, which is the gap
    /// the move exists to close.
    function testAdminSharedTrips() external {
        selectScenarioFork();
        grantEmergencyToSafe();
        vm.prank(safe);
        orchestrator.grantRole(bytes32(0), timelock);
        record(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        vm.expectRevert(
            abi.encodeWithSelector(OrchestratorUnexpectedRoleHolder.selector, address(orchestrator), bytes32(0), safe)
        );
        harness.callAssertInstance(safe);
    }

    /// @notice Before any record the timelock must not hold admin either.
    function testTimelockAdminBeforeRecordTrips() external {
        selectScenarioFork();
        vm.prank(safe);
        orchestrator.grantRole(bytes32(0), timelock);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrchestratorUnexpectedRoleHolder.selector, address(orchestrator), bytes32(0), timelock
            )
        );
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

    /// @notice Neither governance principal ever holds `MINT_ROLE` or
    /// `BURN_ROLE`, recorded or not.
    function testPrincipalHoldingMintOrBurnTrips() external {
        selectFork(LibRainDeploy.BASE);
        bytes32[2] memory roles = [mintRole, burnRole];
        for (uint256 i = 0; i < roles.length; i++) {
            for (uint256 j = 0; j < 2; j++) {
                selectScenarioFork();
                address holder = j == 0 ? safe : timelock;
                vm.prank(safe);
                orchestrator.grantRole(roles[i], holder);
                vm.expectRevert(
                    abi.encodeWithSelector(
                        OrchestratorUnexpectedRoleHolder.selector, address(orchestrator), roles[i], holder
                    )
                );
                harness.callAssertInstance(safe);
            }
        }
    }

    /// @notice After the admin move the timelock is the account that can
    /// grant operating roles, so the drift checks must hold there too:
    /// the timelock taking `EMERGENCY`, either principal taking `MINT` or
    /// `BURN`, and the Safe losing `EMERGENCY` each trip.
    function testPostMoveDriftTrips() external {
        selectFork(LibRainDeploy.BASE);
        bytes32[3] memory roles = [emergencyRole, mintRole, burnRole];
        for (uint256 r = 0; r < roles.length; r++) {
            for (uint256 h = 0; h < 2; h++) {
                if (roles[r] == emergencyRole && h == 0) continue;
                selectPostMoveScenario();
                address holder = h == 0 ? safe : timelock;
                vm.prank(timelock);
                orchestrator.grantRole(roles[r], holder);
                vm.expectRevert(
                    abi.encodeWithSelector(
                        OrchestratorUnexpectedRoleHolder.selector, address(orchestrator), roles[r], holder
                    )
                );
                harness.callAssertInstance(safe);
            }
        }

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
