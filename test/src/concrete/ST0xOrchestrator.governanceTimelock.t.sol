// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.7.0/proxy/beacon/BeaconProxy.sol";

import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {GovernanceTimelockSeatTest} from "../lib/GovernanceTimelockSeatTest.sol";

/// @title ST0xOrchestratorGovernanceTimelockTest
/// @notice `initialize` seats the bound governance timelock as
/// `DEFAULT_ADMIN_ROLE` and all three admin roles, holds no operating role
/// for it, and leaves the deploying account nothing.
contract ST0xOrchestratorGovernanceTimelockTest is GovernanceTimelockSeatTest {
    UpgradeableBeacon internal beacon;

    function setUp() external {
        beacon = new UpgradeableBeacon(address(new ST0xOrchestrator()), address(this));
    }

    function seat() internal override returns (address) {
        return address(new BeaconProxy(address(beacon), abi.encodeCall(ST0xOrchestrator.initialize, ())));
    }

    function assertSeated(address seated, address timelock) internal view override {
        ST0xOrchestrator o = ST0xOrchestrator(payable(seated));
        bytes32[4] memory adminRoles =
            [o.DEFAULT_ADMIN_ROLE(), o.MINT_ADMIN_ROLE(), o.BURN_ADMIN_ROLE(), o.EMERGENCY_ADMIN_ROLE()];
        for (uint256 i = 0; i < adminRoles.length; i++) {
            assertTrue(o.hasRole(adminRoles[i], timelock), "timelock missing an admin role");
            assertFalse(o.hasRole(adminRoles[i], address(this)), "deployer holds an admin role");
        }
        bytes32[3] memory operatingRoles = [o.MINT_ROLE(), o.BURN_ROLE(), o.EMERGENCY_ROLE()];
        for (uint256 i = 0; i < operatingRoles.length; i++) {
            assertFalse(o.hasRole(operatingRoles[i], timelock), "timelock holds an operating role");
            assertFalse(o.hasRole(operatingRoles[i], address(this)), "deployer holds an operating role");
        }
    }
}
