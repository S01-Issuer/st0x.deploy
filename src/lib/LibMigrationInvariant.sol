// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @notice `actual` is neither the accepted pre-migration nor the accepted
/// post-migration state, and the migration deadline has not yet passed. The
/// live chain has drifted onto a value neither side of the migration expects.
/// @param label Human-readable identifier for the invariant being asserted
/// (e.g. `"STOX_RECEIPT_VAULT_BEACON_V1.owner()"`).
/// @param expectedPre The accepted state before the migration runs.
/// @param expectedPost The accepted state after the migration runs.
/// @param actual The value read from the live chain.
error MigrationStateDrift(string label, bytes32 expectedPre, bytes32 expectedPost, bytes32 actual);

/// @notice The migration deadline has passed but `actual` is still not the
/// post-migration value.
/// @param label Human-readable identifier for the invariant being asserted.
/// @param expectedPost The accepted state after the migration runs.
/// @param actual The value read from the live chain.
/// @param deadline The unix timestamp past which only the post-state passes.
error MigrationDeadlinePassed(string label, bytes32 expectedPost, bytes32 actual, uint256 deadline);

/// @title LibMigrationInvariant
/// @notice Reusable dual-state invariant helper with a deadline:
///
/// - A migration script mutates some on-chain value from `pre` to `post`.
/// - A live-fork invariant test asserts, against the head of the target
///   network, that the value is either `pre` (script has not run yet) or
///   `post` (script has run) — while `block.timestamp < deadline`.
/// - Once `block.timestamp >= deadline`, only `post` passes.
///
/// @dev `block.timestamp` is read once per call from the current chain. A
/// live-fork test at chain head sees real time, so cron picks up the
/// deadline transition automatically without any per-test warping.
library LibMigrationInvariant {
    /// @notice Assert `actual` matches the migration acceptance window for
    /// the current time. Before `deadline`: `actual` must be `pre` OR `post`.
    /// At or after `deadline`: `actual` must be `post`.
    /// @param label Human-readable identifier for the invariant surfaced in
    /// revert data — pick something that unambiguously names the on-chain
    /// slot being asserted (e.g. `"STOX_RECEIPT_VAULT_BEACON_V1.owner()"`).
    /// @param actual The value read from the live chain.
    /// @param pre The accepted state before the migration runs.
    /// @param post The accepted state after the migration runs.
    /// @param deadline Unix timestamp past which only `post` is accepted.
    function assertMigration(string memory label, bytes32 actual, bytes32 pre, bytes32 post, uint256 deadline)
        internal
        view
    {
        // A date on a rollout plan, not a race: the window is days wide, so the
        // seconds a validator could skew cannot change which side of it we are on.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= deadline) {
            if (actual != post) {
                revert MigrationDeadlinePassed(label, post, actual, deadline);
            }
        } else if (actual != pre && actual != post) {
            revert MigrationStateDrift(label, pre, post, actual);
        }
    }

    /// @notice `address` overload. Casts each address to `bytes32` under the
    /// hood via `uint160`.
    ///
    /// The zero address is rejected as `actual` unconditionally — on either
    /// side of the deadline, even when `pre` or `post` equals zero. Zero is
    /// the default/renounced/unset value of every address-valued surface
    /// this lib asserts (owners, role holders), so it is always drift, never
    /// an accepted side: a `post` pin of zero means the post-state is
    /// unreachable, and a renounced-to-zero owner trips drift rather than
    /// reading as migrated.
    /// @param label Human-readable identifier for the invariant surfaced in
    /// revert data.
    /// @param actual The value read from the live chain.
    /// @param pre The accepted state before the migration runs.
    /// @param post The accepted state after the migration runs.
    /// @param deadline Unix timestamp past which only `post` is accepted.
    function assertMigration(string memory label, address actual, address pre, address post, uint256 deadline)
        internal
        view
    {
        if (actual == address(0)) {
            revert MigrationStateDrift(
                label, bytes32(uint256(uint160(pre))), bytes32(uint256(uint160(post))), bytes32(0)
            );
        }
        assertMigration(
            label,
            bytes32(uint256(uint160(actual))),
            bytes32(uint256(uint160(pre))),
            bytes32(uint256(uint160(post))),
            deadline
        );
    }

    /// @notice `uint256` overload. Casts each value to `bytes32` under the
    /// hood.
    /// @param label Human-readable identifier for the invariant surfaced in
    /// revert data.
    /// @param actual The value read from the live chain.
    /// @param pre The accepted state before the migration runs.
    /// @param post The accepted state after the migration runs.
    /// @param deadline Unix timestamp past which only `post` is accepted.
    function assertMigration(string memory label, uint256 actual, uint256 pre, uint256 post, uint256 deadline)
        internal
        view
    {
        assertMigration(label, bytes32(actual), bytes32(pre), bytes32(post), deadline);
    }
}
