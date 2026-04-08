# Pass 5 — Correctness / Intent Verification

Scope: verify that every named item (function, comment, constant, test) does what it claims.

## Status of prior-run findings (2026-04-07-01)

- **A03-P5-1 (CRITICAL)** — NatSpec claim "Migration is lazy ... rasterized on first interaction" didn't hold for fresh accounts: **FIXED** on PR4 (cursor advancement now happens regardless of balance; the implementation matches the documented invariant). Pass 3 P3-5 in this run proposes a doc enrichment to make the balance-vs-cursor distinction explicit; the *intent* gap is closed.
- **A01-P5-1 (MEDIUM)** — four `*OfType` getters used `CompletionFilter.ALL` with no way for oracle consumers to filter: **FIXED** on PR6 (`4c2b7eb`). The getters now take an explicit `CompletionFilter` parameter and the interface NatSpec documents the semantics.
- **A21-P5-1 (INFO)** — `unmigrated` storage field name is semantically misleading: still open as INFO. Not re-raised as a new item; carried forward.

## New findings (this run)

### P5-1 — `_migrateAccount` NatSpec phrase "pending completed splits" is internally contradictory

**Severity:** INFO

**Location:** `src/concrete/StoxReceiptVault.sol:58-61`

```solidity
/// @dev Migrate a single account through all pending completed splits.
/// `internal` (rather than `private`) so test harnesses derived from this
/// contract can exercise the migration logic in isolation.
```

"Pending completed splits" is an oxymoron — "pending" means "not yet effective" and "completed" means "effective" in this codebase's vocabulary (see `ICorporateActionsV1.sol:41-48` for the formal definitions via `CompletionFilter`). The intent is "all completed splits this account has not yet been migrated through" — i.e., completed splits whose index is past the account's current cursor.

A reader parsing the NatSpec could misunderstand the semantics as "splits that are both scheduled and effective" (tautology) or "splits that straddle the pending/completed boundary" (nonsense). Actual behavior is closer to "untraversed completed splits."

**PR attribution:** **PR4 (#21)** — where `_migrateAccount` was introduced.

**Proposed fix:** `.fixes/P5-1.md` — rephrase to "through all completed splits not yet applied to this account."

### P5-2 — `CompletionFilter` enum NatSpec mentions only forward-walk semantics, omitting prevOfType early-break behavior

**Severity:** INFO

**Location:** `src/lib/LibCorporateActionNode.sol:28-39`

```solidity
/// @dev Filter for traversal based on completion status.
/// - ALL: return any matching node regardless of completion.
/// - COMPLETED: return only nodes with effectiveTime <= block.timestamp.
///   Since the list is time-ordered and completed nodes are contiguous at
///   the front, forward walks stop early at the first pending node.
/// - PENDING: return only nodes with effectiveTime > block.timestamp.
///   Forward walks skip completed nodes at the front.
```

The enum NatSpec says "forward walks stop early at the first pending node" (COMPLETED filter) and "Forward walks skip completed nodes" (PENDING filter). It is **silent on what backward walks do**. `prevOfType` at line 95 contains the symmetric early-break: `if (filter == CompletionFilter.PENDING && isCompleted) break;` — which reads as the mirror optimization but isn't mentioned in the enum doc.

A reader of the enum who only skims the forward-walk sentences might not realize `prevOfType` with PENDING filter also benefits from an early break, and could be surprised that the same `CompletionFilter` enum drives asymmetric behavior between forward and backward walks.

**PR attribution:** **PR3 (#23)** — where the enum was introduced / renamed to `CompletionFilter`.

**Proposed fix:** `.fixes/P5-2.md` — extend the enum NatSpec with backward-walk sentences.

### P5-3 — `unmigrated` storage field name still misleading (carried forward A21-P5-1)

**Severity:** INFO

**Location:** `src/lib/LibCorporateAction.sol:59-65`

Same text as 2026-04-07-01 A21-P5-1 — the name "unmigrated" suggests "balance not yet migrated" but the semantics is "sum of stored balances of accounts whose migration cursor is k." Renaming across a stack is painful and the field has a correct comment; leaving as INFO and carrying forward. No new fix file; recommend deferring indefinitely unless a natural refactor triggers it.

**PR attribution:** **PR5 (#24)** — where the field was introduced.

## Items deliberately not flagged — verified intent matches implementation

I traced each of the following claims against the code and confirmed the behavior matches:

- `LibCorporateAction.schedule`: "effectiveTime must be strictly in the future" ↔ `if (effectiveTime <= block.timestamp) revert EffectiveTimeInPast(...);`. ✓
- `LibCorporateAction.schedule` tied-time insertion: NatSpec says nothing explicit about tied ordering, but the `<=` comparison in the tail walk produces stable insertion at the back of equal-time runs, confirmed by `testScheduleTiedEffectiveTimeStableOrdering` and `testScheduleTiedEffectiveTimeInMiddleStableOrdering`. ✓
- `LibCorporateAction.cancel` "The node data remains in the array but is no longer reachable" ↔ sets `prev = next = effectiveTime = 0` but leaves `actionType` and `parameters` intact. ✓
- `LibCorporateActionNode.nextOfType` docstring "Start after this node (exclusive). Pass 0 to start from the head of the list." ↔ `current = fromIndex == 0 ? s.head : s.nodes[fromIndex].next;`. Exclusive, head-on-zero. ✓
- `LibRebase.migratedBalance` "Cursor advancement is performed even when `storedBalance == 0`" ↔ fast-path loop at lines 52-59 walks completed splits and returns the latest cursor. ✓
- `LibTotalSupply.fold` "Bootstrap from OZ's totalSupply on first completed split" ↔ `if (firstIndex == 0) return; s.unmigrated[0] = LibERC20Storage.getTotalSupply(); s.totalSupplyBootstrapped = true;`. ✓
- `LibTotalSupply.onMint` / `onBurn` "no-op when `!totalSupplyBootstrapped`" ↔ the bootstrap gate at lines 158-160 / 166-168. ✓
- `LibTotalSupply.effectiveTotalSupply` pure walking recurrence `running = trunc(running * m) + unmigrated[p]` ↔ lines 97-102 implement exactly this formula, cross-verified by the in-test reference implementation `_referenceEffectiveTotalSupply`. ✓
- `CorporateActionScheduled` event `actionIndex The 1-based index assigned to the new action` ↔ `s.nodes.push(); actionIndex = s.nodes.length - 1;` produces 1-based indices (sentinel at 0). ✓
- `LibERC20Storage` slot math: `mstore(0x00, account); mstore(0x20, slot); keccak256(0x00, 0x40)` matches Solidity's `mapping(address => uint256)` storage layout. `_totalSupply` at `slot + 2` matches OZ v5's `ERC20Storage` struct order. Runtime-verified by `LibERC20Storage.t.sol`. ✓
- `StoxCorporateActionsFacet._authorize` "reads the vault's authorizer state via `address(this).authorizer()`" — the `OffchainAssetReceiptVault(payable(address(this))).authorizer()` cast + call reads the vault's authorizer slot via the inherited OARV method. When delegatecalled, `address(this)` is the vault, so the storage read is the vault's. ✓
- `completedActionCount` definition ("An action is complete when its effectiveTime has passed") ↔ `LibCorporateAction.countCompleted()` walks via `nextOfType(0, max, COMPLETED)` which filters by `effectiveTime <= block.timestamp`. ✓
- `ICorporateActionsV1` traversal getter semantics for the three `CompletionFilter` values match the implementation in `LibCorporateActionNode` (verified by `testFacetTraversalGettersFilterParameter` which walks each getter × each filter). ✓

## Files carried forward by reference

Non-stack source files have no new Pass 5 findings.
