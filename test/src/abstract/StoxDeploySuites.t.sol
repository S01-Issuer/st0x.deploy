// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    DEPLOYED_ADDRESS as TOFU_DECIMALS_ADDRESS,
    BYTECODE_HASH as TOFU_DECIMALS_CODEHASH
} from "rain-tofu-erc20-decimals-deploy-0.1.5/src/generated/0_1_0/TOFUTokenDecimals.sol";

import {LibTOFUTokenDecimals} from "rain-tofu-erc20-decimals-0.1.4/src/lib/LibTOFUTokenDecimals.sol";

contract StoxDeploySuitesTest is Test {
    function testTofuPinIsTheDeploymentSourceReaches() external pure {
        assertEq(TOFU_DECIMALS_ADDRESS, address(LibTOFUTokenDecimals.TOFU_DECIMALS_DEPLOYMENT));
        assertEq(TOFU_DECIMALS_CODEHASH, LibTOFUTokenDecimals.TOFU_DECIMALS_EXPECTED_CODE_HASH);
    }
}
