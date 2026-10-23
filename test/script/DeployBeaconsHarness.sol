// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

import {DeployBeacons, boundZoltuDeployStep} from "../../script/20261022-deploy-beacons.s.sol";

/// @dev Exposes the script's internals.
contract DeployBeaconsHarness is DeployBeacons {
    function callAssertTimelockOwned(address beacon) external view {
        assertTimelockOwned(beacon);
    }

    function callBoundZoltuDeployStep(string memory network, address deployer, bytes memory creationCode)
        external
        returns (address)
    {
        return boundZoltuDeployStep(vm, network, deployer, creationCode);
    }
}
