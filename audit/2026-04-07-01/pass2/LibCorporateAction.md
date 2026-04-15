# A21 — Pass 2 (Test Coverage): LibCorporateAction

**Source:** `src/lib/LibCorporateAction.sol`
**Tests:** Indirect via `test/src/concrete/StoxCorporateActionsFacet.t.sol::LibHarness` and `test/src/lib/LibStockSplit.t.sol::StockSplitHarness`

## Coverage observed

- `getStorage()`: indirect via every other library call
- `resolveActionType`: tested for STOCK_SPLIT_TYPE_HASH and unknown
- `schedule`: tested for empty/single/ordering/past-revert
- `cancel`: tested for unlink/complete-revert/non-existent/middle
- `countCompleted`: tested empty and with completed nodes
- `head`/`tail`/`headNode`/`tailNode`: indirectly via the harness; `headNode`/`tailNode` not directly invoked from any test

## Findings

### A21-P2-1 — No test for tied-effectiveTime insertion ordering

**Severity:** LOW

**Location:** `src/lib/LibCorporateAction.sol:134` (tied-time insertion uses `<=`)

When two actions are scheduled at the exact same `effectiveTime`, the `<=` comparison in the insertion walk causes the new node to be inserted **after** the existing node. This is a well-defined design choice (stable insertion at the back of equal-time runs) but no test asserts the resulting order. A regression that flips the comparison to `<` would silently change ordering and break time-stable iteration.

**Suggested fix:** see `.fixes/A21-P2-1.md`. Adds `testScheduleTiedEffectiveTimeStableOrdering`.

### A21-P2-2 — `headNode()` / `tailNode()` accessors are not directly tested

**Severity:** INFO

The accessors return either the sentinel (when the list is empty) or the head/tail node. The empty-list path returning the sentinel (`s.nodes[0]`) requires `s.nodes.length > 0` (otherwise `s.nodes[0]` reverts). The current implementation only ever calls `headNode`/`tailNode` from places that have already pushed at least one node, but the accessor itself doesn't guard against empty arrays. Worth a unit test that calls them on a fully empty storage to confirm the documented behavior. INFO; no fix file.

## Items not flagged

- The ERC-7201 storage slot constant is verified at runtime by `testStorageSlotCalculation` (`StoxCorporateActionsFacet.t.sol:109`).
- `cancel` boundary at `effectiveTime == block.timestamp`: tested by `testCancelCompleteReverts` which warps past 1500 to 2000, but a tighter `effectiveTime == block.timestamp` test would still be reasonable; not strictly required because `<=` semantics are exercised by the warp.
