// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title ICorporateActionsV1
/// @notice Versioned interface for corporate actions on a vault. External
/// consumers — oracles, lending protocols, wrapper contracts — import this
/// interface rather than the concrete facet so they can depend on a stable API
/// while the implementation evolves behind it.
///
/// Both the ERC-20 receipt vault and the ERC-1155 receipts are rebasing tokens.
/// The rebase lifecycle is:
///   1. An authorized scheduler calls `scheduleCorporateAction` with a future
///      `effectiveTime`.
///   2. When `block.timestamp >= effectiveTime`, the split is in effect. No
///      on-chain transaction is needed — time simply passes.
///   3. From this point, `balanceOf` and `totalSupply` return rebased values
///      (original * multiplier) WITHOUT emitting `Transfer` events, even though
///      stored balances have not been rewritten yet.
///   4. The first transaction that touches any account (transfer, mint, burn)
///      triggers lazy migration: the account's stored balance is rasterized to
///      the post-split value and written directly to storage inside `_update`.
///
/// INTEGRATOR WARNINGS:
///
/// Do not cache `balanceOf` across blocks — it can change between any two
/// calls without a `Transfer` event if a split's effective time passes in
/// between.
///
/// Do not compute balances from `Transfer` events alone — event-sourced
/// indexers that sum `Transfer` events will diverge from `balanceOf` after a
/// split. Supplement with:
///   - `CorporateActionEffective`: emitted the first time any transaction
///     touches the vault after a split becomes effective. Fires BEFORE any
///     per-account migration in the same transaction. Use as a trigger to
///     re-poll `balanceOf` for all tracked accounts.
///   - `AccountMigrated`: emitted per account when its stored balance is
///     rasterized on first touch post-split. Not emitted for zero-balance
///     accounts.
///   - `ReceiptAccountMigrated`: same, for ERC-1155 receipt balances.
///
/// `wasEffectiveAt` on `CorporateActionEffective` is almost always in the past
/// relative to the emitting block. It records when the split was scheduled to
/// take effect, not when the first transaction observed it. The gap is however
/// many blocks elapsed between `effectiveTime` and the first post-effectiveTime
/// transaction.
///
/// Balance deltas around a transfer include both the transfer amount and any
/// pending rebase. Example: Alice has 100 raw shares, a 2x split has landed
/// but she has not been migrated yet. Bob has 0 shares.
///   alice.transfer(bob, 50)
///   Alice: raw 100 -> migrated to 200 -> minus 50 = 150
///   Bob: raw 0 -> migrated to 0 -> plus 50 = 50
/// An integrator checking balanceAfter(alice) - balanceBefore(alice) sees
/// 150 - 100 = +50 (but alice sent 50, so they would expect -50). The +100
/// from migration offsets the -50 from the transfer. Check `AccountMigrated`
/// in the same transaction to separate the rebase delta from the transfer
/// delta.
///
/// Use `convertToAssets` on the ERC-4626 wrapper rather than computing share
/// value from `totalSupply`. The wrapper captures rebases in share price, so
/// `convertToAssets` always reflects the post-rebase underlying value without
/// the caller needing to know about splits.
interface ICorporateActionsV1 {
    /// @notice Emitted when a corporate action is successfully scheduled.
    /// @param sender The msg.sender that called `scheduleCorporateAction`.
    /// @param actionIndex The 1-based index assigned to the new action.
    /// @param actionType The bitmap action type (e.g. `ACTION_TYPE_STOCK_SPLIT`).
    /// @param effectiveTime The timestamp at which the action becomes effective.
    event CorporateActionScheduled(
        address indexed sender, uint256 indexed actionIndex, uint256 actionType, uint64 effectiveTime
    );

    /// @notice Emitted when a previously scheduled action is cancelled before
    /// its `effectiveTime`.
    /// @param sender The msg.sender that called `cancelCorporateAction`.
    /// @param actionIndex The action index that was cancelled.
    event CorporateActionCancelled(address indexed sender, uint256 indexed actionIndex);

    /// @notice Emitted the first time any transaction touches the vault after
    /// a corporate action's `effectiveTime` has passed. Fires before any
    /// per-account migration in the same transaction.
    /// @param actionIndex The 1-based index of the action that became effective.
    /// @param actionType The bitmap action type.
    /// @param wasEffectiveAt The scheduled effective time (almost always in the
    /// past relative to the emitting block).
    event CorporateActionEffective(uint256 indexed actionIndex, uint256 actionType, uint64 wasEffectiveAt);

    /// @notice Emitted when an account's stored ERC-20 balance is rasterized
    /// to the post-rebase value on first touch after a stock split.
    /// @param account The account whose balance was migrated.
    /// @param fromCursor The account's migration cursor before this migration.
    /// @param toCursor The account's migration cursor after this migration.
    /// @param oldBalance The stored balance before rasterization.
    /// @param newBalance The stored balance after rasterization.
    event AccountMigrated(
        address indexed account, uint256 fromCursor, uint256 toCursor, uint256 oldBalance, uint256 newBalance
    );

    /// @notice Emitted when an account's ERC-1155 receipt balance is
    /// rasterized to the post-rebase value on first touch after a stock split.
    /// @param account The account whose receipt balance was migrated.
    /// @param id The ERC-1155 token ID.
    /// @param fromCursor The account's migration cursor before this migration.
    /// @param toCursor The account's migration cursor after this migration.
    /// @param oldBalance The stored balance before rasterization.
    /// @param newBalance The stored balance after rasterization.
    event ReceiptAccountMigrated(
        address indexed account, uint256 indexed id, uint256 fromCursor, uint256 toCursor, uint256 oldBalance, uint256 newBalance
    );

    /// @notice Schedule a new corporate action.
    /// @param typeHash External identifier for the action type, e.g.
    /// keccak256("StockSplit"). Resolved to an internal bitmap by the lib.
    /// @param effectiveTime When the action takes effect. Must be in the future.
    /// @param parameters ABI-encoded parameters specific to the action type.
    /// @return actionIndex Handle for the scheduled action.
    function scheduleCorporateAction(bytes32 typeHash, uint64 effectiveTime, bytes calldata parameters)
        external
        returns (uint256 actionIndex);

    /// @notice Cancel a scheduled action whose effectiveTime hasn't passed.
    /// @param actionIndex The scheduled action handle to cancel.
    function cancelCorporateAction(uint256 actionIndex) external;

    /// @notice Count of all completed corporate actions. An action is complete
    /// when its effectiveTime has passed. The Nth completed action has
    /// completedActionId = N.
    function completedActionCount() external view returns (uint256);
}
