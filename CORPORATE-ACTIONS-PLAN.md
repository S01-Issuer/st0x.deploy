# Corporate Actions Implementation Plan

As-built roadmap for the corporate actions system. The stack originally
planned four PRs; the delivered work is six PRs plus one outstanding PR for
receipt coordination. Each PR has comprehensive unit tests with fuzz coverage
on numeric and state-transition logic.

> **Historical note.** This document was previously a pre-implementation plan
> with a stored SCHEDULED/COMPLETE status enum, a "global version counter" for
> rebases, and completion-time-assigned monotonic IDs. The as-built system
> replaced all three with simpler primitives: completion is derived from
> `effectiveTime <= block.timestamp` (no stored status), rebase tracking is a
> per-account cursor into the list (no global counter), and action handles are
> 1-based array indices assigned at schedule time (stable from the moment of
> creation). The original wording is preserved in git history.

## PR 1 — Diamond Facet Shell and Interface (`feat/corporate-actions-pr1-diamond-facet`, PR #18)

Diamond facet architecture wiring: the vault delegatecalls the facet;
the facet writes to ERC-7201 namespaced storage at
`rain.storage.corporate-action.1`. Versioned interface
`ICorporateActionsV1` exposes the public API; external consumers depend on
the interface, not the concrete facet.

**Scope delivered.** `StoxCorporateActionsFacet`, `ICorporateActionsV1`,
`LibCorporateAction` storage skeleton, authorizer wiring via
`OffchainAssetReceiptVault.authorizer()` with distinct
`SCHEDULE_CORPORATE_ACTION` / `CANCEL_CORPORATE_ACTION` permission hashes.
Per-action context (`typeHash`, `effectiveTime`, `parameters`) is forwarded
to the authorizer so per-action policies are expressible.

**Testing.** Facet routing via delegatecall, storage isolation between
harnesses sharing the same facet implementation, ERC-7201 slot pin, auth
permission constants, per-action authorizer context forwarding.

## PR 2 — Doubly Linked List and Action Lifecycle (`feat/corporate-actions-pr2-linked-list`, PR #22)

Doubly linked list of corporate action nodes ordered by `effectiveTime`.
Nodes are stored in a dynamic array with index 0 as a sentinel; real nodes
start at index 1. Each node carries `actionType` (bitmap), `effectiveTime`,
`prev`, `next`, and ABI-encoded `parameters`.

**Scope delivered.** `LibCorporateAction.schedule`, `cancel`,
`countCompleted`, `headNode`, `tailNode`, `head`, `tail`; struct and traversal
primitives split into `LibCorporateActionNode` (`CorporateActionNode`,
`CompletionFilter` enum, `nextOfType` / `prevOfType`). Node insertion walks
backward from the tail and splices in maintaining time order, with stable
ordering for ties in `effectiveTime` (new entries placed after existing
equal-time nodes). Cancellation unlinks a node and marks it cancelled via
`effectiveTime = 0`; `actionType` and `parameters` remain (see `cancel`
NatSpec for the orphan-node invariant and double-cancel guard). Schedule and
cancel events are emitted on the facet.

**Key invariants.**
- The list is always ordered by `effectiveTime` (stable for ties).
- Inserting a node with `effectiveTime <= block.timestamp` reverts.
- Nodes with `effectiveTime <= block.timestamp` cannot be cancelled.
- Cancellation fully unlinks a node; the stored `effectiveTime = 0` sentinel
  is the double-cancel detection guard and must not be removed.
- Action handles (`actionIndex`) are 1-based array indices, assigned at
  schedule time and stable until the contract is redeployed.

**Testing.** Fuzzed insertion ordering, head/middle/tail inserts, past-time
insertion reverts, fuzzed cancellation with list-integrity checks, completed
vs scheduled cancellation, `countCompleted` across time advancement, tied
`effectiveTime` stable-ordering regression tests, event emission.

## PR 3 — Action Types, Filtering, and List Reads (`feat/corporate-actions-pr3-action-types`, PR #23)

Bitmap action types with stock splits as the first concrete type, and the
read/traversal primitives that consume the type mask.

**Scope delivered.** `ACTION_TYPE_STOCK_SPLIT = 1 << 0`,
`STOCK_SPLIT_TYPE_HASH = keccak256("StockSplit")`,
`LibCorporateAction.resolveActionType` mapping external type hashes to
internal bitmaps and validating parameters. `LibStockSplit.validateParameters`
enforces multiplier bounds: the coefficient must be strictly positive,
`trunc(1e18 * multiplier) >= 1` (rejects near-zero multipliers that wipe
balances), and `trunc(1e18 * multiplier) <= 1e36` (rejects near-saturation
multipliers that risk overflow). Traversal uses the `CompletionFilter` enum:
`ALL`, `COMPLETED`, `PENDING`, plumbed through `nextOfType` and `prevOfType`
with optimized early-breaks for monotonic walks.

**Key design points.**
- Bitmap filtering (`actionType & mask != 0`) skips non-matching nodes in a
  single bitwise op.
- Stock split parameters are `abi.encode(Float)` — the Rain Float multiplier.
- External consumers use human-readable type hashes; the contract converts
  to bitmap internally.
- `CompletionFilter` disambiguates "as of now" (COMPLETED) from "everything
  in the schedule" (ALL) vs "scheduled but not yet effective" (PENDING).

**Testing.** Bitmap filtering with random masks, stock split scheduling and
time-advancement lifecycle, cursor-based partial traversal, pending-action
queries, stock split multiplier bounds (min, max, zero, negative).

## PR 4 — Lazy Rebase and Direct Storage Writes (`feat/corporate-actions-pr4-rebase`, PR #21)

Balance effects: lazy migration via the `_update` hook, direct writes to OZ
ERC20 storage, and a `balanceOf` override that returns effective balances
without state changes.

**Scope delivered.** `LibERC20Storage` for direct assembly reads/writes to
OZ v5's ERC-7201 namespaced ERC20 storage (`_balances` mapping and
`_totalSupply`). `LibRebase.migratedBalance` walks completed stock split
nodes from the account's cursor, applying each multiplier sequentially with
rasterization between steps. `StoxReceiptVault` overrides `balanceOf()`
(view-only effective balance), `_update()` (migrates sender and recipient
before the operation), and introduces `accountMigrationCursor[account]` as
the per-account migration pointer.

**Key design points.**
- Migration walks the linked list from the account's cursor, applying
  multipliers for each completed stock split node.
- Direct storage writes avoid the semantic confusion of mint/burn (a stock
  split is redenomination, not value creation), and eliminate spurious
  Transfer events, totalSupply interference, and reentrancy concerns.
- `balanceOf()` is a view function that applies multipliers without state
  changes; the actual rasterization happens lazily on the next `_update`
  touch.
- Both sender and recipient are migrated before any transfer executes.
- Zero-balance accounts still advance their cursor through completed splits
  even though no multiplier math runs. This is load-bearing: a subsequent
  mint or transfer-in would otherwise land at a stale cursor and re-apply
  completed multipliers to a balance that was already written at the
  post-rebase basis. See `audit/2026-04-07-01/pass1/LibRebase.md::A26-1`.
- "1 share = 1 share" — new mints after a split are in current terms.

**Testing.** Fuzzed migration convergence (active vs dormant accounts reach
identical balances), the `100 × (1/3) × 3 × (1/3) × 3 → 99` regression case
with rasterization between steps, zero-balance cursor advancement regression
test, `LibERC20Storage` runtime invariant test against OZ's ERC20Upgradeable,
fuzzed transfers between accounts at different migration states.

## PR 5 — Rebase-Aware totalSupply (`feat/corporate-actions-pr5-total-supply`, PR #24)

Per-cursor pots for accurate totalSupply tracking under lazy migration.

**Scope delivered.** `LibTotalSupply` with `effectiveTotalSupply` (view),
`fold` (bookkeeping update in `_update`), `onAccountMigrated`, `onMint`,
`onBurn`. `CorporateActionStorage` grows: `unmigrated` mapping (per-cursor
balance pots), `totalSupplyLatestSplit` (cursor into the list tracking the
latest stock split `fold` has seen), `totalSupplyBootstrapped` flag.
`StoxReceiptVault.totalSupply()` returns `effectiveTotalSupply`.

**Per-cursor pot mechanics.** Applying a multiplier to an aggregate sum
overestimates relative to the sum of individually-rasterized balances
(`trunc(sum * m) >= sum(trunc(a_i * m))`). Collapsing a migrate into a single
aggregate subtract/add doesn't improve precision. Splitting the aggregate
into separate per-cursor pots does: an account migrating from cursor k to
cursor k' has its stored balance subtracted from `unmigrated[k]` (pre-
multiplier) and its individually-rasterized balance added to `unmigrated[k']`
(post-multiplier), replacing an aggregate estimate with an exact value.

`effectiveTotalSupply` walks completed splits from the bootstrap pot forward,
applying each multiplier and adding each cursor's pot. When all accounts
have migrated through all completed splits, `unmigrated[0..latest-1]` are
zero and `unmigrated[latest]` equals the exact sum of all rasterized
balances — the overestimate fully resolves.

**Key invariants.**
- After `_migrateAccount(account)` in `_update` (which runs after `fold()`),
  `accountMigrationCursor[account] == totalSupplyLatestSplit`. This is
  load-bearing for `onBurn` — the sender's migrated balance must already
  live in `unmigrated[totalSupplyLatestSplit]` when `onBurn` subtracts from
  it, otherwise the pot underflows.
- `sum_over_holders(balanceOf) <= totalSupply()`, with the gap bounded by
  (number of migrated accounts × number of completed splits) wei.

**Testing.** Reference-implementation fuzz comparing `effectiveTotalSupply`
against a naive sum-of-balances oracle, `onBurn` underflow regression tests,
fold / migrate interleaving.

## PR 6 — External Traversal Interface (`feat/corporate-actions-pr6-external-interface`, PR #25)

Node-based traversal API for oracle integration.

**Scope delivered.** `ICorporateActionsV1.latestActionOfType`,
`earliestActionOfType`, `nextOfType`, `prevOfType` — each taking a
`(uint256 mask, CompletionFilter filter)` pair and returning a cursor plus
the node's `actionType` and `effectiveTime`. Cursors are opaque handles for
continued traversal. The `CompletionFilter` enum lets oracles read as-of-now
(`COMPLETED`) history cleanly, or walk the full schedule (`ALL`), or query
only future actions (`PENDING`).

**Testing.** Comprehensive coverage of all four getters across all filter
modes, cursor continuation, empty-list behavior, mask filtering.

## PR 7 — Receipt Coordination (outstanding)

Receipt tokens (ERC-1155) represent the same underlying positions as vault
shares (ERC-20). A rebase on the share side without a matching adjustment
on the receipt side creates an arbitrage opportunity: a holder with both a
receipt and a share could, after a 2x split lands on shares only, redeem the
unchanged receipt for the pre-split unit of underlying while the share is
now worth double.

**Not in the current stack.** Until this PR lands, stock splits MUST NOT be
scheduled on a live deployment. This is the single material gap between the
as-built system and the spec.

The vault already has a manager relationship with the receipt contract
(`receipt().managerMint()` / `managerBurn()`), so the plumbing is in place.
PR #7 will extend the per-account cursor model to receipt holders, apply
matching multipliers via the manager interface, and extend the invariant
harness (landed in PR #6) to cover receipt/share proportionality.

Detailed design — per-receipt-holder cursor semantics, ERC-1155 batch vs
single semantics, the eager-vs-lazy rebase choice for receipts — will be
drafted as a sub-plan before implementation.

## Integration Testing

Once PR #7 lands, a final integration test suite covers end-to-end scenarios:
schedule a split, advance time past `effectiveTime`, transfer between
migrated and unmigrated accounts, mint new shares, burn shares, verify
receipt / share proportionality, query history via the traversal interface,
walk the list with various masks. Fork testing against deployed
infrastructure follows once contracts land on a testnet.
