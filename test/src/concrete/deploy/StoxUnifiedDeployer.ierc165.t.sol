// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {StoxUnifiedDeployer} from "../../../../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {IStoxUnifiedDeployerV1} from "../../../../src/interface/IStoxUnifiedDeployerV1.sol";

contract StoxUnifiedDeployerIERC165Test is Test {
    function testStoxUnifiedDeployerIERC165(bytes4 badInterfaceId) external {
        vm.assume(badInterfaceId != type(IERC165).interfaceId);
        vm.assume(badInterfaceId != type(IStoxUnifiedDeployerV1).interfaceId);

        StoxUnifiedDeployer deployer = new StoxUnifiedDeployer();

        assertTrue(deployer.supportsInterface(type(IERC165).interfaceId));
        assertTrue(deployer.supportsInterface(type(IStoxUnifiedDeployerV1).interfaceId));
        assertFalse(deployer.supportsInterface(badInterfaceId));
    }
}
