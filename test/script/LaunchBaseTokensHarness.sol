// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LaunchBaseTokens} from "../../script/20261020-launch-base-tokens.s.sol";
import {TokenPlan} from "../../src/lib/LibLaunchPlan.sol";
import {LibLedger, LedgerRow} from "../../script/lib/LibLedger.sol";
import {LibProdLaunchBase} from "../../src/lib/LibProdLaunchBase.sol";

/// @notice `LaunchBaseTokens` with each stage's broadcast replaced by a prank
/// of the launch signer: forge cannot broadcast inside a test's call frame.
/// Everything the stages read and check is unchanged.
contract LaunchBaseTokensHarness is LaunchBaseTokens {
    function requireSigner(address) internal pure override {}

    function startLaunchBroadcast() internal override {
        vm.startPrank(LibProdLaunchBase.LAUNCH_SIGNER, LibProdLaunchBase.LAUNCH_SIGNER);
    }

    function stopLaunchBroadcast() internal override {
        vm.stopPrank();
    }

    function exposedAppendLedger(string memory path, LedgerRow[] memory rows) external {
        LibLedger.append(path, rows);
    }

    function exposedAssertLaunched(TokenPlan memory p, address vault, address temp) external view {
        assertLaunched(p, vault, temp);
    }

    function exposedHexQuantity(uint256 value) external pure returns (string memory) {
        return hexQuantity(value);
    }
}
