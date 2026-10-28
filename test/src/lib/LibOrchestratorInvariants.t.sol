// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {LibRainDeploy} from "rain-deploy-0.1.25/src/lib/LibRainDeploy.sol";

import {
    LibOrchestratorInvariants,
    OrchestratorInstanceMissing,
    OrchestratorRoleAdminUnexpected,
    OrchestratorVaultLogicUnexpected
} from "../../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {BeaconOwnerMismatch} from "../../../src/lib/LibBeaconInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibOrchestratorInvariantsHarness} from "./LibOrchestratorInvariantsHarness.sol";
import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {IST0xOrchestratorV1} from "../../../src/interface/deprecated/IST0xOrchestratorV1.sol";

/// @title LibOrchestratorInvariantsTest
/// @notice The orchestrator invariants against every deployment network at
/// head, and each invariant tripped on a Base fork.
contract LibOrchestratorInvariantsTest is Test {
    LibOrchestratorInvariantsHarness internal harness;
    address internal safe;
    address internal timelock;
    IAccessControl internal orchestrator = IAccessControl(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);

    function selectFork(string memory network) internal {
        vm.createSelectFork(network);
        harness = new LibOrchestratorInvariantsHarness();
        safe = LibSafeInvariants.safeForChainId(block.chainid);
        timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    /// @notice The invariants hold at head on every network ST0x deploys to.
    function testLiveOnEveryDeploymentNetwork() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            selectFork(networks[i]);
            harness.callAssertBeaconSet();
            harness.callAssertInstance();
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

    /// @notice Each operating role must be administered by
    /// `DEFAULT_ADMIN_ROLE`.
    function testRoleAdminChangedTrips() external {
        selectFork(LibRainDeploy.BASE);
        ST0xOrchestrator typed = ST0xOrchestrator(payable(address(orchestrator)));
        bytes32[4] memory roles = [bytes32(0), typed.MINT_ROLE(), typed.BURN_ROLE(), typed.EMERGENCY_ROLE()];
        for (uint256 i = 0; i < roles.length; i++) {
            vm.clearMockedCalls();
            vm.mockCall(
                address(orchestrator),
                abi.encodeCall(IAccessControl.getRoleAdmin, (roles[i])),
                abi.encode(keccak256("OTHER_ADMIN"))
            );
            vm.expectRevert(
                abi.encodeWithSelector(
                    OrchestratorRoleAdminUnexpected.selector,
                    address(orchestrator),
                    roles[i],
                    bytes32(0),
                    keccak256("OTHER_ADMIN")
                )
            );
            harness.callAssertInstance();
        }
    }

    /// @notice An instance address with no code trips its own error rather
    /// than reverting on the first call into it.
    function testInstanceWithoutCodeTrips() external {
        selectFork(LibRainDeploy.BASE);
        vm.etch(address(orchestrator), "");
        vm.expectRevert(abi.encodeWithSelector(OrchestratorInstanceMissing.selector, address(orchestrator)));
        harness.callAssertInstance();
    }

    /// @notice The instance's vault-logic lock must pass.
    function testVaultLogicUnexpectedTrips() external {
        selectFork(LibRainDeploy.BASE);
        vm.mockCall(
            address(orchestrator), abi.encodeCall(IST0xOrchestratorV1.vaultLogicIsExpected, ()), abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(OrchestratorVaultLogicUnexpected.selector, address(orchestrator)));
        harness.callAssertInstance();
    }
}
