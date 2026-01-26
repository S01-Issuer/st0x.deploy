// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {StoxUnifiedDeployer} from "src/concrete/deploy/StoxUnifiedDeployer.sol";
import {LibExtrospectBytecode} from "lib/rain.extrospection/src/lib/LibExtrospectBytecode.sol";
import {LibProdDeploy} from "src/lib/LibProdDeploy.sol";

contract StoxUnifiedDeployerProdBaseTest is Test {
    function testProdStoxUnifiedDeployerBase() external {
        StoxUnifiedDeployer fresh = new StoxUnifiedDeployer();

        assertEq(address(fresh).codehash, LibProdDeploy.PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1);
    }
}
