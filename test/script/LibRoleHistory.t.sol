// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRoleHistory} from "../../script/lib/LibRoleHistory.sol";

contract LibRoleHistoryTest is Test {
    function testWindowsCoverTheRequestedRangeWithoutOvershooting() external pure {
        assertEq(LibRoleHistory.nextWindow(100, 2000, 5000), 2099);
        assertEq(LibRoleHistory.nextWindow(2100, 2000, 5000), 4099);
        assertEq(LibRoleHistory.nextWindow(4100, 2000, 5000), 5000);
        assertEq(LibRoleHistory.nextWindow(5000, 2000, 5000), 5000);
        assertEq(LibRoleHistory.nextWindow(4500, 500, 5000), 4999);
    }

    function testRefusedWindowsShrinkUntilTheFailureIsPropagated() external {
        uint256[7] memory sizes = [uint256(2000), 1000, 500, 250, 125, 62, 31];
        for (uint256 i = 0; i < 6; i++) {
            assertEq(LibRoleHistory.shrink(sizes[i], hex"1234"), sizes[i + 1]);
        }
        vm.expectRevert(bytes(hex"1234"));
        this.shrink(31, hex"1234");
    }

    function testMinimumWindowRethrowsTheExactRpcFailure() external {
        bytes memory reason = abi.encodeWithSignature("Error(string)", "RPC refused logs");
        vm.expectRevert(reason);
        this.shrink(50, reason);
        assertEq(LibRoleHistory.shrink(51, reason), 25);
    }

    function shrink(uint256 size, bytes memory reason) external pure returns (uint256) {
        return LibRoleHistory.shrink(size, reason);
    }
}
