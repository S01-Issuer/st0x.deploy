# A22 — Pass 2 (Test Coverage): LibCorporateActionNode

**Source:** `src/lib/LibCorporateActionNode.sol`
**Tests:** Indirect via `test/src/concrete/StoxCorporateActionsFacet.t.sol::LibHarness` (`nextOfType`, `prevOfType`)

## Coverage observed

- `nextOfType` with COMPLETED filter — `testNextOfTypeCompletedFilters`, `testNextOfTypeCompletedEmpty`
- `nextOfType` with ALL filter — `testNextOfTypeAll`
- `nextOfType` with PENDING filter — `testNextOfTypePending`
- `prevOfType` with ALL filter — `testPrevOfType`

## Findings

### A22-P2-1 — `prevOfType` is only tested with `CompletionFilter.ALL`; COMPLETED and PENDING branches uncovered

**Severity:** LOW

**Location:** `src/lib/LibCorporateActionNode.sol:87-109`

The `prevOfType` function has the same three-branch filter logic as `nextOfType`. Only the ALL branch is tested. The PENDING-on-completed early-break at line 95 (`if (filter == CompletionFilter.PENDING && isCompleted) break;`) is never executed, and the COMPLETED match case is never asserted to return the right index when walking backwards from the tail.

This is the symmetric counterpart of `nextOfType`'s PENDING coverage. Adding three tests (`testPrevOfTypeCompleted`, `testPrevOfTypePending`, `testPrevOfTypePendingEarlyBreak`) closes the gap.

**Suggested fix:** see `.fixes/A22-P2-1.md`.

### A22-P2-2 — Empty-list fast path not directly tested

**Severity:** INFO

When `s.head == 0`, `nextOfType(0, ...)` returns 0 immediately. `testNextOfTypeCompletedEmpty` schedules and cancels an action to land in this state, which exercises the cancellation interaction but not a never-scheduled path. A direct test on a freshly constructed harness with no schedule calls would isolate the empty-list behavior. INFO.
