// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer
} from "../../../../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {
    IStoxWrappedTokenVaultBeaconSetDeployerV1
} from "../../../../src/interface/IStoxWrappedTokenVaultBeaconSetDeployerV1.sol";

contract StoxWrappedTokenVaultBeaconSetDeployerIERC165Test is Test {
    function testStoxWrappedTokenVaultBeaconSetDeployerIERC165(bytes4 badInterfaceId) external {
        vm.assume(badInterfaceId != type(IERC165).interfaceId);
        vm.assume(badInterfaceId != type(IStoxWrappedTokenVaultBeaconSetDeployerV1).interfaceId);

        StoxWrappedTokenVaultBeaconSetDeployer deployer = new StoxWrappedTokenVaultBeaconSetDeployer();

        assertTrue(deployer.supportsInterface(type(IERC165).interfaceId));
        assertTrue(deployer.supportsInterface(type(IStoxWrappedTokenVaultBeaconSetDeployerV1).interfaceId));
        assertFalse(deployer.supportsInterface(badInterfaceId));
    }
}
