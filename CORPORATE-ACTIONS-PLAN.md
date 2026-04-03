# Corporate Actions Implementation Plan

Four PRs, each building on the last. Every PR must have comprehensive unit tests with fuzz testing on all numeric and state-transition logic.

## PR 1: Diamond Facet Shell and Interface

Establish that the diamond facet architecture works with the existing vault, and define the versioned interface that all consumers will use.

**Scope**: `ICorporateActionsV1` interface defining the public API for corporate actions. A facet contract implementing the interface, with `LibCorporateAction` providing ERC-7201 namespaced storage. Authorization wiring that distinguishes scheduling from cancellation permissions. The deliverable is a vault that successfully delegates calls to the facet, reads/writes diamond storage, and external contracts can interact via the versioned interface.

**Testing**: Verify facet routing works — calls to corporate action selectors hit the facet, calls to existing vault selectors still work. Fuzz the storage slot calculation to confirm no collisions with existing vault storage. Test authorization — scheduling calls from unauthorized addresses revert, cancellation calls from unauthorized addresses revert, correctly authorized calls succeed. Verify the interface is correctly implemented by the facet.

## PR 2: Doubly Linked List and Action Lifecycle

Implement the core data structure: a doubly linked list ordered by `effectiveTime`, with automatic execution (actions become COMPLETE when their effective time passes) and cancellation support. No specific action types yet — the list operates on generic action nodes with a type bitmap, effective time, and parameters blob.

**Scope**: `LibCorporateAction` grows to include the doubly linked list data structure with insertion logic that maintains time ordering. Each node has previous/next pointers, status (SCHEDULED or COMPLETE), effective time, action type (bitmap), and ABI-encoded parameters. Monotonic IDs are assigned to actions only when their effective time passes — future actions have no ID. Insertion in the past reverts. Cancellation removes a SCHEDULED node from the list. The facet exposes scheduling and cancellation entry points. Events are emitted on scheduling, completion, and cancellation.

**Key invariants**:
- The list is always ordered by effective time
- No node can be inserted with an effective time in the past
- COMPLETE actions are immutable — they cannot be cancelled or modified
- Monotonic IDs are gap-free and only assigned to completed actions
- Cancellation removes the node entirely (updates previous/next pointers)

**Testing**: Fuzz insertion ordering — generate random sequences of effective times and verify the list maintains time order after every insertion. Test insertion at head, tail, and middle of the list. Test that inserting an action with effective time in the past reverts. Fuzz cancellation — cancel random nodes and verify list integrity (previous/next pointers are correct, no dangling references). Test automatic completion — advance block timestamp past an action's effective time, trigger a state check, verify the action transitions to COMPLETE with the correct monotonic ID. Test that completed actions cannot be cancelled. Verify event emission matches state transitions exactly.

The library should be structured so its core logic can be tested in isolation without deploying the full vault. Pure functions where possible, internal functions tested through a thin harness contract.

## PR 3: Action Types, Filtering, and List Reads

Implement bitmap action types with stock splits as the first concrete type, and the read/traversal logic for walking the linked list.

**Scope**: Bitmap constants for action types (`1 << 0` for stock splits, with room for future types). A helper function that converts action type identifiers to bitmap values. Stock split parameter validation — the multiplier must be expressible as a Rain float without precision loss. Traversal functions that walk the list from the tail backwards, accepting a bitmap mask to filter by action type. Query functions: get action by ID, get pending actions, get the most recent action matching a mask. The multiplier from a completed stock split is stored and retrievable by its monotonic ID.

**Key design points**:
- Traversal starts from the tail because pending actions are at the end and recent history is more relevant
- Bitmap filtering: `actionType & mask != 0` skips non-matching nodes in a single operation
- Stock split parameters are `abi.encode(Float)` — the Rain float multiplier
- The global version counter for balance-affecting actions increments when a stock split completes (distinct from the monotonic action ID, which covers all action types)

**Testing**: Test bitmap filtering — create actions of multiple types, traverse with various masks, verify only matching types are returned. Fuzz split ratio validation — generate random ratios and verify the validation correctly accepts clean ratios and rejects problematic ones. Test the complete lifecycle for a stock split: schedule it, advance time past effective time, verify it transitions to COMPLETE with correct ID and stored multiplier. Test traversal from tail with various list sizes and action distributions. Test the helper function maps type identifiers to correct bitmap values. Fuzz the monotonic ID assignment to confirm it is sequential and gap-free across action types.

## PR 4: Rebase and Migration

The final PR implements balance effects: lazy migration via the `_update` hook using direct storage writes, `balanceOf` override for correct read-time balances, and eager `totalSupply` adjustment.

**Scope**: Override `balanceOf()` to return the effective balance (stored balance with pending multipliers applied via Rain float math). Override `_update()` to migrate both sender and recipient before applying the operation. Migration reads the stored balance directly from the ERC20 storage slot, applies sequential multipliers, and writes the result back — no minting, no burning, no Transfer events. Direct assembly access to OZ v5's ERC-7201 namespaced ERC20 storage (`_balances` mapping and `_totalSupply`). When a balance-affecting action completes, `totalSupply` is eagerly updated via direct storage write. Per-account version tracking against the global balance-affecting action counter.

**Key design points**:
- Migration uses the traversal logic from PR 3 to find applicable multipliers between the account's version and the current global version
- Direct storage writes avoid semantic confusion (minting ≠ redenomination) and eliminate reentrancy, spurious events, and totalSupply side effects
- `totalSupply` is an overestimate after migration due to per-account rounding — bounded by (number of holders × rebases) wei, negligible with 18-decimal tokens
- `balanceOf()` is a view function that applies multipliers without state changes
- Both sender and recipient are migrated before any transfer executes

**Testing**: Fuzz the core migration logic heavily — generate random sequences of multipliers and random account interaction patterns, verify that all accounts converge to the same effective balance regardless of when they transact. Test the 1/3 × 3 × 1/3 × 3 = 99.999... case explicitly as a regression test. Fuzz transfers between accounts at different versions — verify both sides are migrated before the transfer executes. Test edge cases: zero balances through migration, near-precision-floor balances, near-overflow balances. Test `balanceOf()` returns the correct effective balance for unmigrated accounts. Test `totalSupply` is immediately correct after a split. Test that new mints after a split are in current-terms ("1 is 1"). Test direct storage writes against OZ's ERC20 by verifying `balanceOf` and `totalSupply` return consistent values through both the override and the standard OZ path.

## Receipt Coordination

Receipt coordination (matching ERC-1155 receipt balances to ERC-20 vault share rebases) may land as part of PR 4 or as a separate PR 5, depending on complexity. The vault-side rebasing and the receipt-side rebasing share the same multiplier data and precision logic, so there is a strong argument for landing them together. But if PR 4 proves too large, receipt coordination can follow immediately after.

## Integration Testing

After all PRs merge, a final integration test suite covers end-to-end scenarios: schedule a split, advance time past effective time, transfer between a migrated and unmigrated account, mint new shares, burn shares, verify receipt consistency, query history from an external contract mock, traverse the list with various masks. Fork testing against deployed infrastructure follows once contracts are on a testnet.
