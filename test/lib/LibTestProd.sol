// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std/StdCheats.sol";

uint256 constant PROD_TEST_BLOCK_NUMBER_BASE = 44600000;

library LibTestProd {
    function createSelectForkBase(Vm vm) internal {
        vm.createSelectFork(vm.envString("RPC_URL_BASE_FORK"), PROD_TEST_BLOCK_NUMBER_BASE);
    }
}
