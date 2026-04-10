# A20 — Pass 3 (Documentation): ICorporateActionsV1

**Source:** `src/interface/ICorporateActionsV1.sol`

## Findings

### A20-P3-1 — Interface NatSpec is silent on the completion semantics of `latestActionOfType` / `earliestActionOfType` / `nextOfType` / `prevOfType`

**Severity:** LOW (paired with A01-P5-1)

**Location:** `src/interface/ICorporateActionsV1.sol:31-77`

```solidity
/// @notice Find the latest (most recent) action matching a type mask.
/// Entry point for walking the list backward from the tail.
```

The four traversal functions describe walking direction and the type mask but never state whether the returned action may be **scheduled-but-not-yet-effective** (pending) or **only effective** (completed). The implementation in `StoxCorporateActionsFacet` uses `CompletionFilter.ALL`, so consumers receive both — but they cannot know this from the interface.

This is critical for oracle integrations (PR6's stated motivation). An oracle asking "what was the latest stock split?" expects "the latest split that has actually taken effect." Receiving a scheduled-but-pending split as the answer leads to incorrect price computations.

By contrast, `completedActionCount` is explicit: `An action is complete when its effectiveTime has passed.` The asymmetry is itself a documentation defect.

**Suggested fix:** see `.fixes/A20-P3-1.md`. The fix may require code changes (split into `latestCompletedActionOfType` vs `latestActionOfType` with explicit names) or a doc clarification with no code change. The triage step decides which.

### A20-P3-2 — Interface doesn't expose action type constants

**Severity:** INFO

**Location:** entire interface

External consumers receive an opaque `uint256 actionType` from the traversal functions. They have to know that `1` means stock split, `2` (when added) means dividend, etc. The interface should either expose these as constants (Solidity supports interface-level constants in 0.8.x) or document a stable mapping in the NatSpec. Today the only place they're defined is `LibCorporateAction.sol` which is not a public surface for oracle integrators.

**Suggested fix:** see `.fixes/A20-P3-2.md`.
