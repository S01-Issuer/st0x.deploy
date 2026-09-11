// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {ClosureCodehashMismatch, ClosureNotDeployed} from "../../../src/lib/LibClosureInvariants.sol";
import {LibClosureInvariantsHarness} from "./LibClosureInvariantsHarness.sol";

/// @title LibClosureInvariantsTest
/// @notice Direct coverage for the "audited contract is live at its pin" gate
/// that five broadcast scripts run in pre-flight. The lib had no test of its
/// own: both refusals were only ever observed THROUGH a script, on a live
/// fork, in whichever state that chain happened to be in — so which branch
/// ran was an accident of on-chain state, and the accept path was never
/// asserted as a distinct outcome at all.
/// @dev Fork-free. Both branches are pure functions of `code.length` and
/// `codehash` at an address, which `vm.etch` sets directly — so every state
/// is reachable deterministically, including the accept path, which needs no
/// chain to have shipped anything.
contract LibClosureInvariantsTest is Test {
    /// @dev An arbitrary non-empty runtime standing in for the audited
    /// closure bytecode. Its content is irrelevant; only its keccak matters,
    /// which is what the pin compares.
    bytes constant AUDITED_CODE = hex"600160005260206000f3";

    /// @dev A DIFFERENT non-empty runtime, for the look-alike case: code is
    /// present, so the deployment check passes, but it is not the audited
    /// bytecode.
    bytes constant IMPOSTOR_CODE = hex"60ff60005260206000f3";

    address constant PIN = address(0xC105E);

    LibClosureInvariantsHarness internal harness;

    function setUp() external {
        harness = new LibClosureInvariantsHarness();
    }

    /// @notice An address with no runtime code is refused by pin, naming the
    /// address so the operator knows which artifact to ship. This is the
    /// pre-bootstrap state of every chain the closure has not reached.
    function testRefusesAnUndeployedPin() external {
        vm.expectRevert(abi.encodeWithSelector(ClosureNotDeployed.selector, PIN));
        harness.callAssertClosureContract(PIN, keccak256(AUDITED_CODE));
    }

    /// @notice Code at the pin is not enough: a contract that is not the
    /// audited bytecode is refused on codehash, and the revert carries both
    /// the expected and the observed hash. This is the check that makes the
    /// pin mean "the audited contract" rather than "some contract".
    function testRefusesACodehashThatIsNotThePin() external {
        vm.etch(PIN, IMPOSTOR_CODE);
        vm.expectRevert(
            abi.encodeWithSelector(
                ClosureCodehashMismatch.selector, PIN, keccak256(AUDITED_CODE), keccak256(IMPOSTOR_CODE)
            )
        );
        harness.callAssertClosureContract(PIN, keccak256(AUDITED_CODE));
    }

    /// @notice The audited bytecode at the pin passes, so the two refusals
    /// above are not vacuous — without this the gate could reject everything
    /// and still look correct.
    function testAcceptsTheAuditedBytecodeAtThePin() external {
        vm.etch(PIN, AUDITED_CODE);
        harness.callAssertClosureContract(PIN, keccak256(AUDITED_CODE));
    }

    /// @notice The deployment check runs BEFORE the codehash check, so an
    /// undeployed pin reverts `ClosureNotDeployed` rather than
    /// `ClosureCodehashMismatch` against `keccak256("")`. Ordering is the
    /// difference between an operator being told "ship the artifact" and
    /// being told "the artifact is wrong".
    function testAnEmptyAccountIsNotReportedAsACodehashMismatch() external {
        vm.expectRevert(abi.encodeWithSelector(ClosureNotDeployed.selector, PIN));
        harness.callAssertClosureContract(PIN, keccak256(""));
    }
}
