// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title ICorporateActionsV1
/// @notice Versioned interface for corporate actions on a vault. External
/// consumers — oracles, lending protocols, wrapper contracts — import this
/// interface rather than the concrete facet so they can depend on a stable API
/// while the implementation evolves behind it.
///
/// Functions are added as the implementation grows across PRs.
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
