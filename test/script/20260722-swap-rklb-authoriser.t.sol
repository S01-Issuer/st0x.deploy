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
/// @dev Unpinned Base head fork: while RKLB is still on V3 the happy path
/// authors the single tx; once the swap EXECUTES on-chain it flips red on
/// `RklbAlreadySwapped` and the post-execution pin PR retires it (the
/// inverted guards keep covering the error paths).
contract SwapRklbAuthoriserTest is Test {
    SwapRklbAuthoriser internal script;

    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        script = new SwapRklbAuthoriser();
    }

    /// @notice Happy path against live Base state: `run()` completes and the
    /// artifact carries exactly one tx targeting the RKLB receipt vault.
    /// Red once the swap executes on-chain (`RklbAlreadySwapped`); retire in
    /// the post-execution pin PR.
    function testRunCompletesAndWritesArtifact() external {
        selectBaseFork();
        script.run();

        string memory json = vm.readFile("out/20260722-rklb-authoriser-swap.json");
        assertEq(
            vm.parseJsonString(json, ".meta.name"),
            "ST0x authoriser swap: RKLB onto the V4 authoriser",
            "artifact bundle name"
        );
        assertEq(
            vm.parseJsonAddress(json, ".transactions[0].to"),
            LibTokenInvariants.RKLB_RECEIPT_VAULT,
            "single tx targets the RKLB receipt vault"
        );
        assertFalse(vm.keyExistsJson(json, ".transactions[1].to"), "no extra txs");
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
