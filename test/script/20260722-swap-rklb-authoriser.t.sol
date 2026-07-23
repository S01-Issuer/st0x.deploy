// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {IAuthorizableV1} from "rain-vats-0.1.6/src/interface/IAuthorizableV1.sol";

import {
    SwapRklbAuthoriser,
    RklbAlreadySwapped,
    UnexpectedRklbAuthoriser
} from "../../script/20260722-swap-rklb-authoriser.s.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibTokenInvariants} from "../../src/lib/LibTokenInvariants.sol";

/// @title SwapRklbAuthoriserTest
/// @notice Live-fork coverage for the RKLB-only swap authoring. RKLB gets a
/// dedicated single-tx bundle because the six-vault bundle from the general
/// swap script was already partially signed when RKLB entered the table —
/// regenerating a combined bundle would void those signatures.
/// @dev Unpinned Base head fork. The swap EXECUTED 2026-07-23, so the happy
/// path is gone: `run()` now reverts `RklbAlreadySwapped` against live Base,
/// which is the state `testRunRevertsWhenAlreadySwapped` asserts directly.
/// What remains is the inverted coverage — already-swapped, unknown
/// authoriser — which is the coverage that keeps meaning something after
/// execution.
contract SwapRklbAuthoriserTest is Test {
    SwapRklbAuthoriser internal script;

    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        script = new SwapRklbAuthoriser();
    }

    /// @notice `run()` reverts `RklbAlreadySwapped` once the vault reports
    /// the V4 authoriser — the exact post-execution state.
    function testRunRevertsWhenAlreadySwapped() external {
        selectBaseFork();
        vm.mockCall(
            LibTokenInvariants.RKLB_RECEIPT_VAULT,
            abi.encodeWithSelector(IAuthorizableV1.authorizer.selector),
            abi.encode(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE)
        );
        vm.expectRevert(
            abi.encodeWithSelector(RklbAlreadySwapped.selector, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE)
        );
        script.run();
    }

    /// @notice `run()` reverts `UnexpectedRklbAuthoriser` on unknown drift.
    function testRunRejectsUnknownAuthoriser() external {
        selectBaseFork();
        address rogue = makeAddr("rogueAuthoriser");
        vm.mockCall(
            LibTokenInvariants.RKLB_RECEIPT_VAULT,
            abi.encodeWithSelector(IAuthorizableV1.authorizer.selector),
            abi.encode(rogue)
        );
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRklbAuthoriser.selector, rogue));
        script.run();
    }
}
