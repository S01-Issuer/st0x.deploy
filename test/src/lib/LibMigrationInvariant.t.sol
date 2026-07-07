// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    LibMigrationInvariant,
    MigrationStateDrift,
    MigrationDeadlinePassed
} from "../../../src/lib/LibMigrationInvariant.sol";
import {LibMigrationInvariantHarness} from "./LibMigrationInvariantHarness.sol";

/// @title LibMigrationInvariantTest
/// @notice Behavioural coverage of the migration invariant helper: both
/// acceptance branches before the deadline, the exact-deadline boundary, the
/// two enforcement branches after the deadline, and the two typed errors it
/// surfaces. Each overload (`bytes32` / `address` / `uint256`) exercises the
/// same underlying decision, so the address and uint256 overloads only need
/// one round-trip test each to prove the cast — the exhaustive branch
/// coverage lives on the `bytes32` overload.
///
/// @dev `block.timestamp` is warped explicitly per test rather than forking a
/// live chain: the helper's decision surface is pure `block.timestamp`
/// comparisons, so cheatcode warping is the tightest way to exercise every
/// branch without pulling in fork state that is irrelevant to what is being
/// tested.
contract LibMigrationInvariantTest is Test {
    LibMigrationInvariantHarness internal harness;

    string internal constant LABEL = "test.invariant";
    bytes32 internal constant PRE = bytes32(uint256(0xAAAA));
    bytes32 internal constant POST = bytes32(uint256(0xBBBB));
    bytes32 internal constant OTHER = bytes32(uint256(0xCCCC));
    uint256 internal constant DEADLINE = 2_000_000_000;

    function setUp() external {
        harness = new LibMigrationInvariantHarness();
    }

    /// @notice Before the deadline, `actual == pre` is accepted: the script
    /// has not yet run and the chain still reports the pre-migration value.
    function testBeforeDeadlineAcceptsPre() external {
        vm.warp(DEADLINE - 1);
        harness.callAssertMigrationBytes32(LABEL, PRE, PRE, POST, DEADLINE);
    }

    /// @notice Before the deadline, `actual == post` is accepted: the script
    /// has already run and the chain now reports the post-migration value.
    function testBeforeDeadlineAcceptsPost() external {
        vm.warp(DEADLINE - 1);
        harness.callAssertMigrationBytes32(LABEL, POST, PRE, POST, DEADLINE);
    }

    /// @notice Before the deadline, `actual` matching neither `pre` nor
    /// `post` trips `MigrationStateDrift` — the chain has landed on a value
    /// the migration does not anticipate on either side of the transition.
    function testBeforeDeadlineRejectsOtherWithDrift() external {
        vm.warp(DEADLINE - 1);
        vm.expectRevert(abi.encodeWithSelector(MigrationStateDrift.selector, LABEL, PRE, POST, OTHER));
        harness.callAssertMigrationBytes32(LABEL, OTHER, PRE, POST, DEADLINE);
    }

    /// @notice At exactly the deadline the helper flips to strict
    /// enforcement — `post` still passes.
    function testAtDeadlineAcceptsPost() external {
        vm.warp(DEADLINE);
        harness.callAssertMigrationBytes32(LABEL, POST, PRE, POST, DEADLINE);
    }

    /// @notice At exactly the deadline the helper flips to strict
    /// enforcement — `pre` no longer passes, trips
    /// `MigrationDeadlinePassed`. This is the forcing-function on the
    /// operator: run the migration or make an explicit choice.
    function testAtDeadlineRejectsPreWithDeadlinePassed() external {
        vm.warp(DEADLINE);
        vm.expectRevert(abi.encodeWithSelector(MigrationDeadlinePassed.selector, LABEL, POST, PRE, DEADLINE));
        harness.callAssertMigrationBytes32(LABEL, PRE, PRE, POST, DEADLINE);
    }

    /// @notice After the deadline, `actual == post` still passes.
    function testAfterDeadlineAcceptsPost() external {
        vm.warp(DEADLINE + 1);
        harness.callAssertMigrationBytes32(LABEL, POST, PRE, POST, DEADLINE);
    }

    /// @notice After the deadline, `actual == pre` trips
    /// `MigrationDeadlinePassed` — the pre-state grace window has closed.
    function testAfterDeadlineRejectsPreWithDeadlinePassed() external {
        vm.warp(DEADLINE + 1);
        vm.expectRevert(abi.encodeWithSelector(MigrationDeadlinePassed.selector, LABEL, POST, PRE, DEADLINE));
        harness.callAssertMigrationBytes32(LABEL, PRE, PRE, POST, DEADLINE);
    }

    /// @notice After the deadline, any drift trips
    /// `MigrationDeadlinePassed` (not `MigrationStateDrift`) — the strict-
    /// enforcement branch is unconditional.
    function testAfterDeadlineRejectsOtherWithDeadlinePassed() external {
        vm.warp(DEADLINE + 1);
        vm.expectRevert(abi.encodeWithSelector(MigrationDeadlinePassed.selector, LABEL, POST, OTHER, DEADLINE));
        harness.callAssertMigrationBytes32(LABEL, OTHER, PRE, POST, DEADLINE);
    }

    /// @notice The `address` overload round-trips through the same
    /// decision — one before-deadline pre acceptance is enough to prove the
    /// `bytes32(uint256(uint160(...)))` cast lands where it should.
    function testAddressOverloadRoundTripsPre() external {
        vm.warp(DEADLINE - 1);
        address pre = address(0x1111111111111111111111111111111111111111);
        address post = address(0x2222222222222222222222222222222222222222);
        harness.callAssertMigrationAddress(LABEL, pre, pre, post, DEADLINE);
    }

    /// @notice The `address` overload surfaces the same
    /// `MigrationStateDrift` selector as the `bytes32` overload when the
    /// value matches neither side — the byte layout of the emitted
    /// revert data is unaffected by which overload was called.
    function testAddressOverloadDriftSurfacesSelector() external {
        vm.warp(DEADLINE - 1);
        address pre = address(0x1111111111111111111111111111111111111111);
        address post = address(0x2222222222222222222222222222222222222222);
        address other = address(0x3333333333333333333333333333333333333333);
        vm.expectRevert(
            abi.encodeWithSelector(
                MigrationStateDrift.selector,
                LABEL,
                bytes32(uint256(uint160(pre))),
                bytes32(uint256(uint160(post))),
                bytes32(uint256(uint160(other)))
            )
        );
        harness.callAssertMigrationAddress(LABEL, other, pre, post, DEADLINE);
    }

    /// @notice The `uint256` overload round-trips through the same decision.
    function testUint256OverloadRoundTripsPre() external {
        vm.warp(DEADLINE - 1);
        harness.callAssertMigrationUint256(LABEL, 1, 1, 3, DEADLINE);
    }

    /// @notice The `uint256` overload surfaces the same
    /// `MigrationDeadlinePassed` selector as the `bytes32` overload after
    /// the deadline has passed.
    function testUint256OverloadDeadlinePassedSurfacesSelector() external {
        vm.warp(DEADLINE + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                MigrationDeadlinePassed.selector, LABEL, bytes32(uint256(3)), bytes32(uint256(1)), DEADLINE
            )
        );
        harness.callAssertMigrationUint256(LABEL, 1, 1, 3, DEADLINE);
    }
}
