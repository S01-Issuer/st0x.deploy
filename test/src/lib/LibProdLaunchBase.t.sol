// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {LibProdLaunchBase} from "../../../src/lib/LibProdLaunchBase.sol";

contract LibProdLaunchBaseTest is Test {
    /// @dev After tDIS's launch, the last sft-ops launch these pins were read
    /// against.
    uint256 constant FORK_BLOCK = 52700000;

    function testPinnedContractsHaveTheirCodehashOnBase() external {
        vm.createSelectFork(LibRainDeploy.BASE, FORK_BLOCK);
        assertEq(LibProdLaunchBase.METABOARD.codehash, LibProdLaunchBase.METABOARD_CODEHASH);
        assertEq(LibProdLaunchBase.CLONE_FACTORY.codehash, LibProdLaunchBase.CLONE_FACTORY_CODEHASH);
    }

    /// @notice The launch signer is an EOA that has launched before.
    function testLaunchSignerIsAnEoaThatHasLaunched() external {
        vm.createSelectFork(LibRainDeploy.BASE, FORK_BLOCK);
        assertEq(LibProdLaunchBase.LAUNCH_SIGNER.code.length, 0);
        assertGt(vm.getNonce(LibProdLaunchBase.LAUNCH_SIGNER), 0);
    }
}
