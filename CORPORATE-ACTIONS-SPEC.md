# Corporate Actions Specification

## Overview

A corporate action like a stock split must adjust the balance of every
token holder simultaneously. Iterating over all holders in a single
transaction is impossible at scale, so the system needs a mechanism that
achieves the economic effect of a simultaneous adjustment without actually
touching every account.

This specification describes five components that together solve this
problem: the diamond facet provides the architectural foundation, the
doubly linked list provides the ordered data structure, action types define
the triggers and their parameters, the rebase system implements the actual
balance adjustments, and the query interface exposes state to external
contracts.

> **As-built document.** This specification reflects the system actually
> delivered in PRs #18 / #22 / #23 / #21 / #24 / #25. An earlier draft of
> this document described a SCHEDULED/COMPLETE status enum, a global
> version counter for rebases, and completion-time-assigned monotonic IDs
> — none of which exist in the as-built system. The earlier draft is
> preserved in git history on this branch.

## Design Principles

### Framework Principles

**Single source of truth.** All corporate action state lives on the vault
itself. External contracts already depend on the vault address for balance
queries — they should not need to discover or trust a separate registry.

**No manual execution, no stored completion state.** Corporate actions take
effect automatically when their `effectiveTime` passes. No one needs to
call a function to "execute" an action, and the system does not store a
status field. Whether an action is pending or has taken effect is derived
at read time from `effectiveTime <= block.timestamp`. This eliminates any
risk of an action's stored state drifting from the clock, and it removes
both the "manual execution" operator failure mode and the associated timezone
concerns for globally distributed teams.

**Extensibility without migration.** The framework supports future corporate
action types (dividends, name changes, mergers) without storage migrations
or vault redeployment. A versioned interface (`ICorporateActionsV1`) ensures
external consumers can depend on a stable API while the implementation
evolves behind it.

### Rebase Principles

**Sequential precision over mathematical equivalence.** Applying multipliers
1/3, 3, 1/3, 3 sequentially to 100 — with rasterization (truncation) to
`uint256` between each step — yields 99, not 100. Collapsing them into a
single 1× multiplier would yield exactly 100. The system must preserve the
sequential, rasterized result. This is not a bug — it is a deliberate choice
that guarantees every account arrives at identical balances regardless of
when they interact with the contract. An account that transferred after
every corporate action and an account that was dormant for a year must
arrive at the same balance when they finally transact. See the worked
example in `LibRebase.sol` for the step-by-step arithmetic.

**Rasterize on write, never scale input.** When a user says "transfer 1
share," that means 1 share in current terms. The system materializes
(rasterizes) the effective balance from stored base balance plus pending
multipliers before applying any operation. Attempting to reverse-engineer
a base amount from a current-terms input would introduce additional
precision errors and break user expectations.

**Migration is invisible.** Account holders never need to call a separate
"migrate" function. Migration happens automatically as a pre-step to any
balance-changing operation (transfer, mint, burn) via the `_update` hook.

## Component 1: Diamond Facet Foundation

### Problem

Corporate actions require substantial logic — scheduling, data structures,
multiplier storage, migration tracking, query interfaces. Adding this
directly to the vault would exceed contract size limits. But the vault
address must remain the single point of contact for external systems.

### Solution

A diamond facet delegatecalls corporate action logic while preserving the
vault's address as the entry point. The facet's storage lives in the vault's
storage space at a collision-resistant ERC-7201 slot
(`rain.storage.corporate-action.1`), consistent with the vault's existing
storage patterns.

The facet exposes its functionality through a versioned interface
(`ICorporateActionsV1`). External consumers — oracles, lending protocols,
wrapper contracts — import the interface rather than the concrete facet.
Callers don't need to know whether they're hitting the facet directly or
through the vault.

The facet integrates with the vault's authorizer via
`OffchainAssetReceiptVault(payable(address(this))).authorizer()`, resolving
the authorizer from the vault's storage under delegatecall. Scheduling and
cancelling have distinct permissions that can be assigned to different
roles: `SCHEDULE_CORPORATE_ACTION` and `CANCEL_CORPORATE_ACTION`. The facet
forwards full per-action context to the authorizer (`typeHash`,
`effectiveTime`, `parameters` for schedule; `actionIndex` for cancel) so
per-action policies — for example, "reject stock splits with a multiplier
magnitude above X" — are expressible in authorizer logic without changes
to the facet.

The facet's entry points assert they are running under delegatecall (via an
immutable `_SELF = address(this)` constant set at construction) and revert
otherwise. This makes the "cannot run standalone" property explicit rather
than relying on the incidental fact that `authorizer()` can't be resolved
on a standalone deployment.

## Component 2: Doubly Linked List and Action Lifecycle

### Problem

Corporate actions must be ordered by time. An action scheduled for next
month and an action scheduled for next week need to be applied in the right
order regardless of when they were created. The system also needs to let
callers distinguish between actions that have taken effect and actions that
are still pending.

A simple sequential array doesn't work because actions might be scheduled
out of order — you might schedule one for June, then one for May. And a
fixed array would require expensive shifting to maintain ordering on
insertion.

### Solution

A doubly linked list ordered by `effectiveTime`, stored as a dynamic array
with index 0 as a sentinel. Real nodes start at index 1, and 0 means "no
node" in pointer fields (`prev`, `next`, `head`, `tail`).

Each node carries:

- `actionType` — the bitmap type (a single `1 << n` bit; see Component 3)
- `effectiveTime` — when the action takes effect
- `prev` / `next` — 1-based indices, 0 = none
- `parameters` — ABI-encoded type-specific payload

There is no stored status field. Whether an action is pending or in effect
is derived at read time from `effectiveTime <= block.timestamp`.

**Action handles.** When an action is scheduled, it is assigned
`actionIndex` — its 1-based position in the dynamic array. This index is
stable from the moment of creation. It is not monotonic in the usual sense
(insertion may place the new node before or after existing ones depending
on its `effectiveTime`), but the array position itself never changes, which
is the property external callers actually need for cancellation and
referencing.

**Insertion.** `schedule` walks backward from the tail, splicing the new
node in at the correct position. Insertion with `effectiveTime <=
block.timestamp` reverts — you cannot retroactively create history.
Tied-`effectiveTime` insertions are stable: new entries are placed after
existing equal-time nodes. The insertion walk is extracted as a private
helper for testability.

**Cancellation.** A node whose `effectiveTime` has not yet passed can be
cancelled. Cancellation unlinks the node from the list (updating `prev` /
`next` pointers and `head` / `tail` if appropriate) and sets
`effectiveTime = 0` as a sentinel marking the node as cancelled. The
`actionType` and `parameters` fields are intentionally not cleared — the
node is unreachable via linked-list traversal, so ghost data is invisible
to consumers that use the list correctly. The `effectiveTime = 0` assignment
is the **double-cancel guard**: a second `cancel` call on the same index
is detected by the `effectiveTime == 0` check and reverts. Removing the
zero-assignment would cause a double-cancel to silently corrupt `head` and
`tail`.

**Automatic effect.** Because completion is derived from `effectiveTime`,
there is no transition, no event, no bookkeeping. A read at block T sees
the action in effect iff `effectiveTime <= T`. This is the single most
important simplification from the original design.

**Why a doubly linked list.** Singly linked lists only allow forward
traversal. Oracles reading recent history typically want "the most recent
action" or "any pending action," both of which naturally start from the
tail. Backward traversal from the tail is gas-efficient under the
expectation that pending actions are rare and recent history is more
relevant than ancient history.

### Lifecycle

```
[does not exist] → scheduled node in the list          (via schedule)
scheduled node   → unreachable, effectiveTime=0        (via cancel, before effectiveTime)
scheduled node   → in-effect node                      (automatic, at effectiveTime)
```

There are no stored intermediate states. "In effect" is not a recorded state
— it is a predicate over `effectiveTime` and `block.timestamp`.

## Component 3: Action Types and Filtering

### Problem

Different corporate actions have different parameters, validation
requirements, and downstream effects. A stock split has a ratio. A name
change has a string. A dividend might have an amount and a record date.
The list stores actions generically — it needs a type system to interpret
them.

External consumers also need to query subsets of actions efficiently. An
oracle only cares about balance-affecting actions; a UI might want all
actions of any type. Iterating through the entire list and checking types
one by one is wasteful unless the type representation supports efficient
filtering.

### Solution

**Bitmap action types.** Internally, each action type is represented as a
single bit in a `uint256` bitmap. The first type is `1 << 0`, the second
`1 << 1`, and so on. This caps the maximum number of distinct action types
at 256 — more than sufficient.

Externally, action types are identified by human-readable hashes
(e.g. `keccak256("StockSplit")`). `LibCorporateAction.resolveActionType`
maps the external identifier to its internal bitmap and validates the
parameters at schedule time. Callers schedule and query using the readable
constants; the contract translates to bitmap internally.

Bitmap representation makes filtering during traversal a single bitwise op:
`actionType & mask != 0` skips non-matching nodes. No if/else chains, no
per-node mapping lookups during iteration.

**Completion filter.** Traversal also takes a `CompletionFilter` enum —
`ALL`, `COMPLETED`, or `PENDING` — that lets callers disambiguate
as-of-now history (`COMPLETED`), the full schedule (`ALL`), or only future
actions (`PENDING`). Oracle integrations reading split history pass
`COMPLETED`; UI dashboards may pass `ALL`.

**Stock splits** are the first concrete action type. A stock split's
parameters encode a Rain Float multiplier — the ratio by which all balances
will be adjusted. `LibStockSplit.validateParameters` enforces that the
multiplier's coefficient is strictly positive, that `trunc(1e18 * multiplier)
>= 1` (rejects near-zero multipliers that would wipe every realistic balance
to zero), and that `trunc(1e18 * multiplier) <= 1e36` (rejects near-
saturation multipliers that risk overflow when applied sequentially). The
bounds are conservative: the largest historical stock split was roughly
1000×, well inside the ceiling, and the smallest realistic reverse split
would be around 1/1000×, well above the floor.

**Filtering reads.** When traversing the list (Component 5), callers
provide both a bitmap mask and a `CompletionFilter`. The traversal skips
any node whose type doesn't match the mask or whose effective-time doesn't
match the filter. This means a single global list serves all use cases —
there is no need for per-type lists, which would complicate insertion and
increase storage costs.

## Component 4: Rebase Implementation

### Problem

This is the hard part. When a stock split's `effectiveTime` passes, every
holder's balance must change by the multiplier. But iterating over all
holders is impossible, and virtual-balance approaches (storing a global
multiplier and computing balances on read) break down when users need to
transfer specific amounts.

Consider: a user holds 100 base shares with pending multipliers that yield
30 effective shares. They want to transfer 1 share. With virtual balances,
the system would need to convert "1 current share" back to base terms
(dividing by the cumulative multiplier), introducing another rounding step
on every single transfer. And the cumulative multiplier itself is wrong —
sequential application of 1/3 × 3 × 1/3 × 3 with rasterization between
steps gives a different result than collapsing to 1×.

The transfer problem makes virtual balances unworkable. The system needs
to materialize effective balances, but only when accounts actually interact.

### Solution

**Lazy migration via `_update`.** Every account stores a
`accountMigrationCursor[account]` — the 1-based index of the last stock
split node this account has been migrated through. The cursor is a direct
reference into the linked list, not a separate version counter. When an
account interacts via transfer, mint, or burn, the `_update` hook walks the
list from the account's cursor forward through every completed stock split
node and applies each multiplier sequentially.

The migration sequence inside `_update`:

1. `LibTotalSupply.fold()` — bootstrap totalSupply tracking on the first
   completed split and advance `totalSupplyLatestSplit` over any new
   completions.
2. `_migrateAccount(from)` — walk sender's cursor, rasterize balance via
   direct storage writes, update cursor to the latest completed split,
   update per-cursor pot accounting.
3. `_migrateAccount(to)` — same for the recipient.
4. For mint (`from == 0`): `LibTotalSupply.onMint(amount)` adds to the
   latest cursor's pot.
5. For burn (`to == 0`): `LibTotalSupply.onBurn(amount)` subtracts from
   the latest cursor's pot.
6. `super._update(from, to, amount)` — apply the actual transfer/mint/burn
   against the now-migrated balances.

Both sender and recipient must be migrated before the transfer executes.
If only the sender is migrated, the transferred amount would land at a
recipient whose stored balance is still in pre-rebase terms, and subsequent
reads would re-apply completed multipliers to a balance that was already
written at the post-rebase basis.

**Zero-balance cursor advancement.** For an account with `storedBalance == 0`,
the multiplier math is a no-op — but the cursor advancement is still
load-bearing. If a fresh recipient with zero balance received a mint or
transfer and the cursor had not been advanced, the recipient's stored
balance (written at the post-rebase basis by `super._update`) would be
read back with every completed multiplier re-applied, silently inflating
the balance. See `audit/2026-04-07-01/pass1/LibRebase.md::A26-1` for the
full reproduction of the bug this prevents, and `LibRebase.migratedBalance`
for the fast-path that still walks the list to advance the cursor even
when balance is zero.

**Direct storage writes.** Migration writes the new balance directly to
the ERC20 storage slot using assembly (`LibERC20Storage.setBalance`), not
via mint or burn. Minting is semantically wrong for a redenomination — a
stock split does not create new economic value, it changes the unit of
account. Direct writes also avoid side effects: no spurious Transfer
events, no recursive `_update` call, no totalSupply side effects from
mint/burn paths.

This couples the implementation tightly to OpenZeppelin v5's
`ERC20Upgradeable` ERC-7201 storage layout (`openzeppelin.storage.ERC20` at
a known namespaced slot). The coupling is documented in the `LibERC20Storage`
SAFETY block and pinned by a runtime invariant test. Bumping OZ past v5 is
a breaking change for this stack — see `CLAUDE.md` §Dependencies.

### Precision

Rain Float math handles all multiplier calculations, preserving exact
fractional representation — a 1/3 multiplier stays as 1/3 through storage
rather than becoming 0.333... in fixed-point.

The sequential rasterize-at-each-step rule means precision loss accumulates
predictably. Applying 1/3, 3, 1/3, 3 to 100 with uint256 truncation between
each step:

```
100 × 1/3 = 33.33… → trunc → 33
 33 × 3   = 99
 99 × 1/3 = 33     → trunc → 33
 33 × 3   = 99
```

The answer is 99, not 100 (the collapsed-multiplier answer) and not
99.999... (the unrasterized continuous answer). This is correct behaviour.
The alternative — collapsing multipliers into a running product — would
give different results depending on *when* an account migrates and through
*which* actions, breaking the invariant that all accounts converge to the
same state.

### `balanceOf` Override

`balanceOf()` is overridden on `StoxReceiptVault` to return the effective
balance — the stored balance with all pending multipliers applied —
without modifying state. External reads always see the correct current
balance, even for accounts that haven't transacted since the last
corporate action. The override reads the stored balance directly from
the ERC20 storage slot (same assembly access used for migration writes)
and calls `LibRebase.migratedBalance`. This is a view function with no
state changes.

### totalSupply: Per-Cursor Pots

The straightforward approach — apply the multiplier to an aggregate
unmigrated sum — overestimates relative to the sum of individually-
rasterized balances, because `trunc(sum * m) >= sum(trunc(a_i * m))`.
Migrating a single account under this model cannot improve precision:
subtracting and adding the same value leaves the aggregate sum unchanged.

**Per-cursor pots.** Instead of one aggregate `unmigrated` number,
`CorporateActionStorage` maintains a separate unmigrated sum per cursor
position: `unmigrated[k]` is the sum of stored balances for accounts whose
migration cursor is `k`. Index 0 is the bootstrap pot (pre-any-split
balances).

`effectiveTotalSupply` walks completed stock split nodes from the bootstrap
pot forward:

```
running = unmigrated[0]
for each completed split node at position p with multiplier m:
    running = trunc(running * m) + unmigrated[p]
totalSupply = running
```

When an account migrates from cursor `k` to cursor `k'`, its stored balance
is subtracted from `unmigrated[k]` (the pre-multiplier pot) and its
individually-rasterized balance is added to `unmigrated[k']` (the post-
multiplier pot). This genuinely improves precision: the aggregate estimate
at `k` is replaced with an exact value at `k'`.

**Convergence.** When all accounts have migrated through all completed
splits, `unmigrated[0..latest-1]` are all zero and `unmigrated[latest]`
equals the exact sum of all rasterized balances. The overestimate fully
resolves.

**Mint/burn tracking.** Mints add `amount` to `unmigrated[totalSupplyLatestSplit]`;
burns subtract from the same pot. This relies on an invariant that is
load-bearing for `onBurn` safety: after `_migrateAccount` runs in `_update`,
the affected account's cursor always equals `totalSupplyLatestSplit`. If
it did not, `onBurn`'s subtraction would target a pot that did not include
the account's balance, and the subtraction would underflow.

**No folding required.** Pots do not need to be folded eagerly when a new
split "completes" — the view function automatically picks up new
multipliers during its walk. `fold()` only bootstraps `unmigrated[0]` on
first use and advances `totalSupplyLatestSplit` for mint/burn tracking. A
`fold()` pass is not a "completion" signal; it is a bookkeeping update
that may run arbitrarily long after `effectiveTime`.

## Component 5: Downstream Query Interface

### Problem

External contracts — oracles, lending protocols, DEX integrations — need
to make decisions based on corporate action state. An oracle needs to know
if a split just happened so it can adjust its price feed. A lending protocol
needs to know if a rebase is imminent so it can pause liquidations during
the transition period.

These contracts call into the vault during their own transaction execution,
so query functions must be gas-efficient for onchain use, not just offchain
reads.

### Solution

The query interface exposes corporate action state through the vault
address (via `ICorporateActionsV1`) as four traversal getters plus a
completed-count accessor:

- `latestActionOfType(mask, filter)` — the most recent action matching the
  mask and filter. Entry point for walking backward from the tail.
- `earliestActionOfType(mask, filter)` — the earliest action matching the
  mask and filter. Entry point for walking forward from the head.
- `nextOfType(cursor, mask, filter)` — the next matching action after the
  cursor. Continues a forward walk.
- `prevOfType(cursor, mask, filter)` — the previous matching action before
  the cursor. Continues a backward walk.
- `completedActionCount()` — walks the list counting nodes whose
  `effectiveTime <= block.timestamp`.

Each traversal getter returns `(cursor, actionType, effectiveTime)`. The
`cursor` is an opaque handle (internally a 1-based index into the node
array) that the caller passes back for continuation. A return cursor of 0
means "no match."

**Completion detection is caller-side.** There is no "has this action taken
effect yet?" boolean in the return tuple. The caller has the action's
`effectiveTime` and their own `block.timestamp` — they can make the
comparison themselves. This keeps the interface small and the detection
logic in one place.

**Reading effective balances.** External consumers do not need a dedicated
getter for effective account balances — they read `balanceOf(account)` on
the vault, which already applies the multiplier chain without state
changes. Same for `totalSupply()`.

## Receipt Coordination (outstanding)

Receipt tokens (ERC-1155) represent the same underlying positions as vault
shares (ERC-20). A rebase on the share side without a matching adjustment
on the receipt side creates an arbitrage opportunity: after a 2x split
lands on shares only, a holder with both a receipt and a share could
redeem the unchanged receipt for the pre-split unit of underlying while
the share is now worth double.

**This is not implemented in the current stack.** Until a follow-up PR
closes this gap, stock splits MUST NOT be scheduled on a live deployment.

The vault already has a manager relationship with the receipt contract —
`receipt().managerMint()` and `receipt().managerBurn()` are used during
deposits and withdrawals — so the plumbing is in place. The follow-up PR
will extend the per-account cursor model to receipt holders, apply matching
multipliers via the manager interface, and extend the invariant harness
(landed in PR #6) to cover receipt/share proportionality.

Detailed design — per-receipt-holder cursor semantics, ERC-1155 batch vs
single semantics, the eager-vs-lazy rebase choice for receipts, and
atomicity requirements — will be drafted as a sub-plan before
implementation.
