# Triage decisions for deferred items — 2026-04-08 walkthrough

User-driven decisions on the 9 items that were DEFERRED in the original triage.
Decisions are recorded here first; implementation happens after the full
walkthrough.

| # | ID | Severity | Decision | Notes |
|---|---|---|---|---|
| 1 | A01-P5-1 | MEDIUM | **(a) Add `CompletionFilter` parameter** | All four `*OfType` getters in `ICorporateActionsV1` get a third parameter; implementation lands on PR6. |
| 2 | A23-1 | MEDIUM | **(a) Runtime invariant test** | New `test/src/lib/LibERC20Storage.t.sol`; lands on PR4. |
| 3 | A27-1 | MEDIUM | **DEFER** | Bound choice still open; revisit before merge. |
| 4 | A01-1 | LOW | **(a) Pass per-action context to authorizer** | `abi.encode(typeHash, effectiveTime, parameters)` for schedule, `abi.encode(actionIndex)` for cancel. Lands on PR1 (where `_authorize` is first defined). |
| 5 | A01-P2-1 | LOW | **(a) Mock-authorizer tests now** | `MockAuthorizer` + 4 facet-level tests on PR1. Also assert the mock receives the per-action context from A01-1. Full authorizer integration tests deferred to follow-up after the real authorizer is written. |
| 6 | A21-1 | LOW | **(c) DISMISSED** — authorizer is the safeguard | No code change. Trusting the authorizer to gate schedulers is the accepted design. |
| 7 | A21-P2-1 | LOW | **(a) Add tied-effectiveTime ordering test** | `testScheduleTiedEffectiveTimeStableOrdering` on PR2. |
| 8 | A26-P2-2 | LOW | **(b) DEFER** | Speculative until a second action type exists. Revisit when the next type is being added. |
| 9 | A28-P2-3 | INFO | **(a) Add fuzz test** | `testFuzzEffectiveTotalSupplyMatchesReference` on PR5. |

## Summary by PR

**PR1 (#18)** — implement A01-1 (per-action context to authorizer), A01-P2-1 (mock authorizer + 4 facet-level tests)
**PR2 (#22)** — implement A21-P2-1 (tied effectiveTime ordering test)
**PR3 (#23)** — nothing
**PR4 (#21)** — implement A23-1 (LibERC20Storage runtime invariant test)
**PR5 (#24)** — implement A28-P2-3 (fuzz effectiveTotalSupply)
**PR6 (#25)** — implement A01-P5-1 (CompletionFilter parameter on the four traversal getters)

Still deferred / dismissed:
- A27-1 (split multiplier bound) — DEFERRED, bound choice open
- A21-1 (unbounded parameters bytes) — DISMISSED
- A26-P2-2 (non-split node interspersing test) — DEFERRED until second action type exists

