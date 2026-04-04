# Corporate Actions Implementation Plan

Four PRs, each building on the last. Every PR must have comprehensive unit tests with fuzz testing on all numeric and state-transition logic.

## PR 1: Diamond Facet Shell and Interface

Establish that the diamond facet architecture works with the existing vault, and define the versioned interface that all consumers will use.

**Scope**: `ICorporateActionsV1` interface defining the public API for corporate actions (using `actionId` for stable action references and `completedActionCount()` for the count of completed actions). A facet contract with `LibCorporateAction` providing ERC-7201 namespaced storage. Authorization wiring with distinct permissions for scheduling and cancellation. The deliverable is a vault that successfully delegates calls to the facet and reads/writes diamond storage.

**Testing**: Verify facet routing works — calls to corporate action selectors hit the facet via delegatecall. Verify storage isolation — two harnesses sharing the same facet impl have independent storage. Verify the ERC-7201 storage slot matches the documented formula. Test authorization permission constants.

## PR 2: Doubly Linked List and Action Lifecycle

Implement the core data structure: a doubly linked list ordered by `effectiveTime`, with automatic completion and cancellation support. No specific action types yet — the list operates on generic action nodes with a type bitmap, effective time, and parameters blob.

**Scope**: `LibCorporateAction` grows to include the doubly linked list with insertion logic that maintains time ordering. Each node has previous/next pointers, effective time, action type (bitmap), and ABI-encoded parameters. There is no stored status — an action is complete when its `effectiveTime <= block.timestamp`. There are no stored counters — `completedActionCount()` walks from the head counting completed nodes. Monotonic completed action IDs are positional indices from the head — they are stable because new actions cannot be inserted in the past. Insertion in the past reverts. Cancellation removes a node from the list (only if its effective time has not passed). Action type validation via `validateActionType()` against a `KNOWN_ACTION_TYPES` bitmap constant (set to `type(uint256).max` in this PR, narrowed in PR 3). The facet exposes scheduling and cancellation entry points. Events are emitted on scheduling and cancellation.

**Key invariants**:
- The list is always ordered by effective time
- No node can be inserted with an effective time in the past or present
- Completed actions (effective time in the past) cannot be cancelled
- Cancellation removes the node entirely (updates previous/next pointers)
- Completed action IDs are positional from the head, gap-free, and stable

**Testing**: Fuzz insertion ordering — generate random sequences of effective times and verify the list maintains time order after every insertion. Test insertion at head, tail, and middle of the list. Test that inserting an action with effective time in the past reverts. Fuzz cancellation — cancel random nodes and verify list integrity (forward/backward walk counts match, previous/next pointers are consistent). Test that completed actions cannot be cancelled. Test `completedActionCount()` returns correct count as time advances. Test zero action type reverts. Test event emission on schedule and cancel.

The library should be structured so its core logic can be tested in isolation without deploying the full vault — internal functions tested through a thin harness contract.

## PR 3: Action Types, Filtering, and List Reads

Implement bitmap action types with stock splits as the first concrete type, and the read/traversal logic for walking the linked list. Narrow `KNOWN_ACTION_TYPES` to only implemented types.

**Scope**: Bitmap constant for stock split action type (`1 << 0`). Narrow `KNOWN_ACTION_TYPES` from `type(uint256).max` to only the implemented types. External-facing type identifiers (hash of action type name, e.g. `keccak256("StockSplit")`) mapped to bitmap values. Stock split parameter validation — the multiplier must be a valid Rain float. Traversal functions: walk completed actions from a cursor with bitmap mask filtering, walk pending actions from the tail backwards. The facet exposes query functions for traversal.

**Key design points**:
- Traversal starts from the tail for pending actions (they are at the end) and from the head/cursor for completed actions
- Bitmap filtering: `actionType & mask != 0` skips non-matching nodes in a single operation
- Stock split parameters are `abi.encode(Float)` — the Rain float multiplier
- External consumers use hash identifiers; the contract converts to bitmap internally

**Testing**: Test bitmap filtering — create actions of multiple types, traverse with various masks, verify only matching types are returned. Test stock split lifecycle: schedule, advance time, verify completion count increments and multiplier is retrievable. Test traversal from cursor — walk partial ranges of completed actions. Test pending action query returns only future actions. Fuzz the bitmap filtering with random masks.

## PR 4: Rebase and Migration

The final PR implements balance effects: lazy migration via the `_update` hook using direct storage writes, `balanceOf` override for correct read-time balances, and eager `totalSupply` adjustment.

**Scope**: `LibERC20Storage` for direct assembly reads/writes to OZ v5's ERC-7201 namespaced ERC20 storage (`_balances` mapping and `_totalSupply`). `LibRebase` walks the corporate action list from the account's migration cursor, applying sequential Rain float multipliers for each completed balance-affecting action. `StoxReceiptVault` overrides `balanceOf()` to return the effective balance (view, no state change) and `_update()` to migrate both sender and recipient before the operation. Migration writes the rasterized balance directly to storage — no mint/burn, no Transfer events, no reentrancy. `totalSupply` is eagerly updated when a balance-affecting action completes. Per-account migration cursor tracks the last action node applied.

**Key design points**:
- Migration walks the linked list from the account's cursor, applying multipliers for completed balance-affecting nodes
- Direct storage writes avoid semantic confusion (minting ≠ redenomination) and eliminate reentrancy, spurious events, and totalSupply side effects
- `totalSupply` is a slight overestimate after migration due to per-account rounding — bounded by (number of holders × rebases) wei, negligible with 18-decimal tokens
- `balanceOf()` is a view function that applies multipliers without state changes
- Both sender and recipient are migrated before any transfer executes
- "1 share = 1 share" — new mints after a split are in current-terms

**Testing**: Fuzz the core migration logic — generate random sequences of multipliers and random account interaction patterns, verify all accounts converge to the same effective balance regardless of when they transact. Test the 1/3 × 3 × 1/3 × 3 = 99 (not 100) case explicitly as a regression test. Fuzz transfers between accounts at different migration states. Test edge cases: zero balances through migration, near-overflow balances. Test `balanceOf()` returns correct effective balance for unmigrated accounts. Test `totalSupply` is immediately correct after a split. Test new mints after a split are in current-terms. Verify direct storage writes produce values consistent with OZ's standard ERC20 path.

## Receipt Coordination

Receipt coordination (matching ERC-1155 receipt balances to ERC-20 vault share rebases) may land as part of PR 4 or as a separate PR 5, depending on complexity.

## Integration Testing

After all PRs merge, a final integration test suite covers end-to-end scenarios: schedule a split, advance time past effective time, transfer between migrated and unmigrated accounts, mint new shares, burn shares, verify receipt consistency, query history from an external contract mock, traverse the list with various masks. Fork testing against deployed infrastructure follows once contracts are on a testnet.
