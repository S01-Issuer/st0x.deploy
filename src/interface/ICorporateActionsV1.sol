// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {CompletionFilter} from "../lib/LibCorporateActionNode.sol";

/// @dev Bitmap action type for V1 stock splits (forward and reverse).
/// External consumers pass this to the traversal getters
/// (`latestActionOfType`, `earliestActionOfType`, `nextOfType`, `prevOfType`)
/// to filter on stock-split actions. Declared at file scope alongside
/// `ICorporateActionsV1` because Solidity does not allow constant access
/// via an interface type (`IFoo.X` rejected).
uint256 constant ACTION_TYPE_STOCK_SPLIT_V1 = 1 << 0;

/// @dev Bitmap action type for V1 stablecoin dividends. Reserved; not yet
/// schedulable.
uint256 constant ACTION_TYPE_STABLES_DIVIDEND_V1 = 1 << 1;

/// @dev Union of all currently defined action types. Traversal getters revert
/// with `InvalidMask` when called with `mask & VALID_ACTION_TYPES_MASK == 0`,
/// since no node can match such a mask.
uint256 constant VALID_ACTION_TYPES_MASK = ACTION_TYPE_STOCK_SPLIT_V1 | ACTION_TYPE_STABLES_DIVIDEND_V1;

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
///
/// ADMIN CAPABILITIES:
///
/// The vault implements an RWA (Real World Asset) compliance model with the
/// following centralized capabilities that integrators must evaluate:
///
/// | Capability               | Trigger                              | Effect                                                       |
/// |--------------------------|--------------------------------------|--------------------------------------------------------------|
/// | Beacon upgrade           | Beacon owner (multi-sig)             | Can replace all token logic at any time                      |
/// | Authorizer swap          | Vault owner                          | Can change which addresses are allowed to transfer           |
/// | Certification freeze     | Certifier role                       | Halts all transfers when `certifiedUntil` expires            |
/// | Confiscation             | Confiscator role                     | Seizes shares or receipts from any address (bypasses freeze) |
/// | Stock split scheduling   | `SCHEDULE_CORPORATE_ACTION` holder   | Multiplies all balances at a future time                     |
/// | Stock split cancellation | `CANCEL_CORPORATE_ACTION` holder     | Removes a pending split before effective time                |
///
/// For lending protocols / AMMs: Your pool can be frozen at any time via the
/// certification mechanism, and individual addresses can be blocklisted via
/// the authorizer. Evaluate whether your protocol can tolerate a temporary
/// inability to move the position.
///
/// For custodians: The confiscation capability means the vault operator can
/// seize assets. This is a regulatory requirement for RWA tokenization but
/// should be disclosed to end users.
///
/// DECIMALS:
///
/// `StoxReceiptVault.decimals()` inherits from the underlying asset (e.g.
/// wrapping USDC yields 6 decimals, wrapping DAI yields 18, other assets
/// yield whatever `asset.decimals()` returns). Do not hardcode 18.
///
/// QUERYING CORPORATE ACTION STATE:
///
/// The vault exposes stock split state through this interface:
///
/// ```solidity
/// // Get the most recent completed stock split.
/// (uint256 cursor, uint256 actionType, uint64 effectiveTime)
///     = vault.latestActionOfType(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
///
/// // Walk backward through all completed splits.
/// while (cursor != 0) {
///     // ... process the split at `cursor` ...
///     (cursor, actionType, effectiveTime)
///         = vault.prevOfType(cursor, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED);
/// }
///
/// // Check for pending (future) splits.
/// (cursor, actionType, effectiveTime)
///     = vault.latestActionOfType(ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.PENDING);
/// ```
///
/// ERC-1155 RECEIPT BATCH READS:
///
/// Both `balanceOf(account, id)` and `balanceOfBatch(accounts, ids)` on the
/// receipt contract return rebased values. They are consistent with each
/// other — a batch read returns the same values as calling `balanceOf` per
/// element.
///
/// EXTENSION MODEL:
///
/// New action types are added as new bitmap bits + new type hashes,
/// alongside existing types in the same chronological linked list. The
/// model is **add a new type next to the old one**, not "evolve the old
/// type in place". To add a new type:
///
/// 1. Pick a new bitmap bit: `ACTION_TYPE_FOO_V1 = 1 << N`. The bitmap is
///    `uint256` so 256 types are addressable.
/// 2. Namespace a new type hash: `keccak256("st0x.corporate-actions.foo.1")`.
///    The trailing `.1` is the schema version; bumping it to `.2` (with
///    a corresponding `ACTION_TYPE_FOO_V2 = 1 << M`) is how an existing
///    type is "versioned" — the V1 nodes keep decoding with V1 logic,
///    V2 nodes dispatch to V2 logic, both coexist in one list.
/// 3. Create a new library `LibFoo` with `validateV1`, `encodeParametersV1`,
///    `decodeParametersV1` — a single-point-of-change for the type's
///    on-chain schema. Co-locating the codec with the validator keeps the
///    schema definition in one place.
/// 4. Extend `LibCorporateAction.resolveActionType`'s if-chain to dispatch
///    the new type hash to the new validator + encoder. This is the
///    intentional extension point — adding a type is a core-library edit
///    and a vault redeployment, not a runtime registration.
/// 5. Extend any consumer that walks the list (today
///    `LibRebase.migratedBalance` for stock splits only) to handle the
///    new action type where relevant. Consumers mask against the
///    specific bit(s) they care about — not equality — so forward-
///    compatibility is preserved when new bits land.
/// 6. Deploy a new vault implementation. Upgrade the beacon.
///
/// Old nodes keep decoding with their old libraries; new nodes dispatch
/// to the new library via their action-type bit. Both coexist in one
/// linked list, time-ordered.
///
/// **What the model handles cleanly:**
///   - New action types with different parameter shapes (the type-erased
///     `bytes` payload is exactly this).
///   - Versioning an existing type (new `_V2` bit + new type hash; old
///     `_V1` nodes keep decoding under the old codec).
///   - Single chronological linked list across all types — consumers
///     traverse in time order regardless of action-type mix.
///
/// **What the model does NOT auto-handle — design discipline applies:**
///   - **Underlying-type drift in `Float` (or any other dependency
///     library).** The V1 decoder calls `abi.decode(params, (Float))`
///     directly. If `rain.math.float` ships a new release with a
///     different mantissa width, old stored parameters silently corrupt
///     when re-decoded. Mitigation: pin the dependency at a specific
///     commit and never bump it across a deployed version. If the
///     dependency must be upgraded, that's a `_V2` action type with a
///     new type hash — old `_V1` parameters keep decoding under the old
///     pinned dependency.
///   - **In-place migration of stored parameters.** Storage bytes do
///     NOT auto-translate. "Re-encode all V1 nodes as V2" requires
///     explicit migration code that walks the list, decodes as V1,
///     re-encodes as V2, and writes back while preserving
///     `effectiveTime` ordering and `prev`/`next` pointers. The default
///     policy is "never migrate, always add a new version" — write any
///     migration code defensively if that policy ever changes.
///   - **Type-level pause / disable.** `cancelCorporateAction(actionIndex)`
///     unlinks one specific node. There is no "disable action type X
///     across the list" primitive; cancelling N pending nodes of type X
///     takes N transactions. If a type-level pause becomes operationally
///     necessary it would need a new storage flag and a new entry point.
///   - **Off-chain discovery of new types.** Indexers learn new bitmap
///     bits and type hashes from the CHANGELOG / release notes — there
///     is no on-chain registry of `(bit, typeHash, name)` mappings.
///     Acceptable at the expected scale (dozens of types lifetime, not
///     hundreds).
///
/// @dev **Action type bitmap.** The `actionType` field returned by the four
/// traversal getters is a single-bit mask identifying the action's type.
/// The canonical constants — `ACTION_TYPE_STOCK_SPLIT_V1`,
/// `ACTION_TYPE_STABLES_DIVIDEND_V1`, and `VALID_ACTION_TYPES_MASK` —
/// are declared at file scope above.
///
/// Further action types will be added as additional bit positions. Consumers
/// should mask against the specific bit(s) they care about, not compare
/// equality — so that pending additions remain forward-compatible.
interface ICorporateActionsV1 {
    /// @notice Emitted when a corporate action is successfully scheduled.
    /// @param sender The msg.sender that called `scheduleCorporateAction`.
    /// @param actionIndex The 1-based index assigned to the new action.
    /// @param actionType The bitmap action type (e.g. `ACTION_TYPE_STOCK_SPLIT_V1`).
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
        address indexed account,
        uint256 indexed id,
        uint256 fromCursor,
        uint256 toCursor,
        uint256 oldBalance,
        uint256 newBalance
    );

    /// @notice Schedule a new corporate action.
    ///
    /// For stock splits, the multiplier in `parameters` is expected to be in the
    /// range 1/100x to 100x per action in practice. The system enforces bounds
    /// of trunc(1e18 * multiplier) in [1, 1e36] — a much wider ceiling designed
    /// for safety rather than operational use. In practice, the multi-sig
    /// scheduler will stay within the real-world range (2x to 10x for forward
    /// splits, 1/2x to 1/10x for reverse splits).
    ///
    /// There is no limit on the number of splits that can accumulate; each one
    /// compounds on the previous. Multiple pending splits at different future
    /// effective times are possible.
    ///
    /// @param typeHash External identifier for the action type, e.g.
    /// keccak256("st0x.corporate-actions.stock-split.1"). Resolved to an internal
    /// bitmap by the lib.
    /// @param effectiveTime When the action takes effect. Must be strictly in
    /// the future: `effectiveTime > block.timestamp`. Scheduling at the exact
    /// current timestamp reverts with `EffectiveTimeInPast`.
    /// @param parameters ABI-encoded parameters specific to the action type.
    /// @return actionIndex Handle for the scheduled action.
    function scheduleCorporateAction(bytes32 typeHash, uint64 effectiveTime, bytes calldata parameters)
        external
        returns (uint256 actionIndex);

    /// @notice Cancel a scheduled action. Only valid while the action is
    /// strictly pending: `block.timestamp < effectiveTime`. At or after the
    /// exact `effectiveTime`, cancel reverts with `ActionAlreadyComplete`.
    /// @param actionIndex The scheduled action handle to cancel.
    function cancelCorporateAction(uint256 actionIndex) external;

    /// @notice Count of all completed corporate actions. An action is complete
    /// when `block.timestamp >= effectiveTime` — i.e. at or after the exact
    /// effective-time block, inclusive.
    function completedActionCount() external view returns (uint256);

    /// @notice Find the latest (most recent) action matching a type mask and
    /// completion filter. Entry point for walking the list backward from the
    /// tail.
    /// @param mask Bitmap mask to filter action types. Must intersect the
    /// currently defined action types — calls with `mask & VALID_ACTION_TYPES_MASK
    /// == 0` (zero mask or only undefined bits) revert with `InvalidMask`.
    /// Use `type(uint256).max` to match every type, including bits reserved
    /// for future additions.
    /// @param filter Completion filter:
    /// - `ALL` returns the most recent action regardless of effectiveTime
    ///   (includes scheduled-but-pending actions);
    /// - `COMPLETED` returns the most recent action whose effectiveTime has
    ///   passed (the typical choice for oracles reading historical state);
    /// - `PENDING` returns the most recent scheduled action whose effectiveTime
    ///   has not yet passed.
    /// @return cursor Opaque handle for continued traversal via `prevOfType`.
    /// 0 if no matching action exists.
    /// @return actionType The action's bitmap type (0 if none).
    /// @return effectiveTime The action's effective timestamp (0 if none).
    function latestActionOfType(uint256 mask, CompletionFilter filter)
        external
        view
        returns (uint256 cursor, uint256 actionType, uint64 effectiveTime);

    /// @notice Find the earliest action matching a type mask and completion
    /// filter. Entry point for walking the list forward from the head.
    /// @param mask Bitmap mask to filter action types — see `latestActionOfType`
    /// for the validity rules; `InvalidMask` reverts apply here too.
    /// @param filter Completion filter — see `latestActionOfType` for the
    /// semantics of `ALL` / `COMPLETED` / `PENDING`.
    /// @return cursor Opaque handle for continued traversal via `nextOfType`.
    /// 0 if no matching action exists.
    /// @return actionType The action's bitmap type (0 if none).
    /// @return effectiveTime The action's effective timestamp (0 if none).
    function earliestActionOfType(uint256 mask, CompletionFilter filter)
        external
        view
        returns (uint256 cursor, uint256 actionType, uint64 effectiveTime);

    /// @notice Walk forward from a cursor to the next matching action.
    /// @param cursor The cursor returned by a previous traversal call. If
    /// the action at this cursor has been cancelled since it was obtained,
    /// its `next` pointer was zeroed by `cancelCorporateAction` and the
    /// walk returns 0 immediately — restart from `earliestActionOfType` to
    /// recover the new list head.
    /// @param mask Bitmap mask to filter action types — see `latestActionOfType`
    /// for the validity rules; `InvalidMask` reverts apply here too.
    /// @param filter Completion filter — see `latestActionOfType`.
    /// @return nextCursor Opaque handle for the next match, or 0 if none.
    /// @return actionType The action's bitmap type (0 if none).
    /// @return effectiveTime The action's effective timestamp (0 if none).
    function nextOfType(uint256 cursor, uint256 mask, CompletionFilter filter)
        external
        view
        returns (uint256 nextCursor, uint256 actionType, uint64 effectiveTime);

    /// @notice Walk backward from a cursor to the previous matching action.
    /// @param cursor The cursor returned by a previous traversal call. If
    /// the action at this cursor has been cancelled since it was obtained,
    /// its `prev` pointer was zeroed and the walk returns 0 immediately —
    /// restart from `latestActionOfType` to recover the new list tail.
    /// @param mask Bitmap mask to filter action types — see `latestActionOfType`
    /// for the validity rules; `InvalidMask` reverts apply here too.
    /// @param filter Completion filter — see `latestActionOfType`.
    /// @return prevCursor Opaque handle for the previous match, or 0 if none.
    /// @return actionType The action's bitmap type (0 if none).
    /// @return effectiveTime The action's effective timestamp (0 if none).
    function prevOfType(uint256 cursor, uint256 mask, CompletionFilter filter)
        external
        view
        returns (uint256 prevCursor, uint256 actionType, uint64 effectiveTime);

    /// @notice Read the ABI-encoded parameters blob for a scheduled or
    /// completed corporate action, given a cursor returned from one of the
    /// traversal getters.
    ///
    /// @dev Intended for cross-contract consumers that need to apply the
    /// action (e.g. the receipt contract reading a stock split multiplier
    /// during its own rebase walk). For stock splits, the returned bytes
    /// decode to a single `Float` via `LibStockSplit.decodeParametersV1`.
    /// Consumers should mask the cursor's `actionType` (via `nextOfType` /
    /// `prevOfType`) before calling this to ensure they know which decoder
    /// to apply.
    ///
    /// Reverts if `cursor` is 0 or points outside the current nodes array.
    /// A cursor that points at a cancelled node returns whatever bytes
    /// were written at schedule time — cancelled nodes intentionally
    /// retain their `actionType` and `parameters` fields so correct
    /// consumers (who must filter cancelled nodes out via their
    /// `effectiveTime == 0` sentinel before dereferencing) can still
    /// inspect them for debugging. See `LibCorporateAction.cancel` for
    /// the orphan-node invariant.
    ///
    /// @param cursor The cursor returned by `nextOfType` / `prevOfType`.
    /// @return parameters The raw ABI-encoded parameters for the action.
    function getActionParameters(uint256 cursor) external view returns (bytes memory parameters);
}
