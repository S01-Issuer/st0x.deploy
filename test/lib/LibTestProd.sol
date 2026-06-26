// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.1/src/StdCheats.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";

uint256 constant PROD_TEST_BLOCK_NUMBER_BASE = 47842154;

library LibTestProd {
    function createSelectForkBase(Vm vm) internal {
        vm.createSelectFork(LibRainDeploy.BASE, PROD_TEST_BLOCK_NUMBER_BASE);
    }
}
