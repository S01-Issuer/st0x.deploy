# A01 — Pass 5 (Correctness / Intent): StoxCorporateActionsFacet

## Findings

### A01-P5-1 — `latestActionOfType` / `earliestActionOfType` / `nextOfType` / `prevOfType` use `CompletionFilter.ALL`, returning pending actions to consumers who reasonably expect "completed" semantics

**Severity:** MEDIUM

**Location:** `src/concrete/StoxCorporateActionsFacet.sol:50, 65, 80, 95`

The four traversal getters all pass `CompletionFilter.ALL` to `LibCorporateActionNode`. This means a scheduled-but-not-yet-effective stock split is returned to the caller as if it were "the latest stock split."

The intent gap:

- `completedActionCount()` is explicit in name and behavior: only completed actions count.
- The four `*OfType` functions are not explicit. The name "latestActionOfType" suggests "as of now" — most consumers reading the name would assume completed-only.
- The PR6 motivation is explicit: "feat: add nextOfType to external interface for **oracle integration**." Oracles asking "what was the latest stock split?" need the answer to mean "the latest split that has actually taken effect onchain." Receiving a scheduled-but-pending split causes the oracle to apply a multiplier prematurely.
- Commit `968b7e5` is titled "refactor: use CompletionFilter.ALL in external facet traversal" — so the choice was deliberate, but the rationale is not documented in NatSpec, the function name, or the commit message body.

**Three possible remediations**, in order of preference:

1. **Split the API** — add `latestCompletedActionOfType` / `latestPendingActionOfType` / `latestActionOfType` (the third returning ALL with explicit name) and similarly for the other three. This is the most expressive and avoids the ambiguity.
2. **Add a `CompletionFilter` parameter** to the interface — `function latestActionOfType(uint256 mask, CompletionFilter filter)` — and let the caller choose. Slightly more verbose but doesn't bake in a default.
3. **Document the ALL semantics** in interface NatSpec and rename the functions to make the inclusion of pending explicit (e.g., `latestKnownActionOfType`).

For oracle integrators, option 1 or 2 is strongly preferred. Today's API gives them no path to filter to completed-only without walking the list themselves.

**Suggested fix:** see `.fixes/A01-P5-1.md`. The fix file proposes option 2 (parameter) as the smallest API change that closes the ambiguity.

**PR attribution:** PR6 (`feat/corporate-actions-pr6-external-interface`).

**Impact:** MEDIUM not HIGH because (a) no funds move through these getters, and (b) consumers can defensively check `effectiveTime <= block.timestamp` themselves. But the principle of least surprise is violated and oracle integrators are the explicit target audience for the API.
