# Guidelines Advisor — 2026-04-09

**Skill:** `building-secure-contracts:guidelines-advisor` (Trail of Bits)
**Scope:** Corporate-actions stack — PRs #18 → #22 → #23 → #21 → #24 → #25, tracking PR #16 (`feat/corporate-actions-diamond-spec`). Files: `src/concrete/StoxCorporateActionsFacet.sol`, `src/concrete/StoxReceiptVault.sol`, `src/interface/ICorporateActionsV1.sol`, `src/lib/{LibCorporateAction, LibCorporateActionNode, LibStockSplit, LibRebase, LibERC20Storage, LibTotalSupply}.sol`, and the corresponding tests.
**Format:** Not a standard audit pass (pass0-5). A planning/review artifact from a skill-driven walkthrough of Trail of Bits' development guidelines, followed by item-by-item user decisions.

## Summary

16 findings: 0 CRITICAL, 4 HIGH (one — receipt coordination — is a spec-level scope gap, not a code defect), 6 MEDIUM, 5 LOW, plus 1 finding that was already covered by an existing test.

User decided each item individually. Outcomes:

| Status     | Count | Items                                      |
|------------|-------|--------------------------------------------|
| Will apply | 11    | 1, 2, 3, 6, 7, 8, 9 (erc20 only), 10, 12, 13, 14, 16 |
| Already covered | 1 | 9 (corp-action slot — test pre-existed)  |
| Deferred   | 4     | 4, 5, 11, 15                               |

## Findings and Decisions

### Item 1 (HIGH) — `onBurn` / cursor invariant fuzz coverage
**Concern.** `LibTotalSupply.onBurn` does `unmigrated[totalSupplyLatestSplit] -= amount`, which underflows if the sender's cursor doesn't equal `totalSupplyLatestSplit` at `onBurn` time. The ordering in `_update` (`fold() → _migrateAccount → onBurn`) enforces the invariant, but it is only safe if the invariant holds for **every** reachable sequence of ops — the exact shape of thing invariant testing catches and point tests miss.
**Decision.** Verify the existing burn/onBurn tests at apply-time. If they pin the `cursor == totalSupplyLatestSplit` invariant in its strongest form, close the item. If present but weaker, rewrite. If absent, add a stateful fuzz.
**Target PR.** #24 (pr5-total-supply).

### Item 2 (HIGH) — Receipt coordination gap
**Concern.** Spec calls for ERC-1155 receipt balances to rebase in lockstep with ERC-20 shares. Current stack has no receipt-side rebase. A user holding both a receipt and a share could, after a split lands on shares only, arbitrage the two representations. Stock splits MUST NOT be scheduled on a live deployment until this lands.
**Decision.** Implement as new top-of-stack PR #7 (`feat/corporate-actions-pr7-receipt-coordination`). Draft a sub-plan (design round) **before** any code. This is the single largest item — expect per-receipt-holder cursor, ERC-1155 batch semantics, manager-hook integration, eager-vs-lazy rebase choice, and an extension of the PR #6 invariant harness to cover receipt/share proportionality.
**Target PR.** New PR #7 (top of stack, after PR #25).

### Item 3 (HIGH) — Facet "cannot run standalone" should be an explicit assertion
**Concern.** Today, direct calls to `StoxCorporateActionsFacet` revert because `OffchainAssetReceiptVault(address(this)).authorizer()` fails to resolve — an implicit safety property. View getters (added in PR #22 / #25) don't hit the authorizer lookup and are callable on a standalone deployment (returning zeroes from the facet's own storage, harmless-but-misleading).
**Decision.** Add `address private immutable _SELF = address(this);` set at construction, plus an `onlyDelegatecalled` modifier that reverts with `FacetMustBeDelegatecalled` when `address(this) == _SELF`. Apply the modifier to every external entry point (schedule/cancel/count and — in later PRs — the four traversal getters). This is the OZ `UUPSUpgradeable.onlyProxy` pattern.
**Target PR.** #18 (pr1-diamond-facet). Later PRs that add new external entry points must apply the modifier to them.
**Note.** Constructor stays parameterless (Zoltu determinism). The facet currently has no pointer file in `src/generated/`, so no pointer regeneration is needed. If a later PR adds one, bytecode will change on the Item 3 commit and pointers must be regenerated at that point.

### Item 4 (HIGH) — Cap scheduled-action list length — **DEFERRED**
**Concern.** Every live read walks the list; an authorized scheduler could spam the list and bloat every transfer's gas cost.
**Decision.** Deferred. Scheduler is a multi-sig; spam is not a realistic threat at this trust model.

### Item 5 (MEDIUM) — `CorporateActionCompleted` event on `fold()` — **DEFERRED**
**Concern.** Off-chain oracles have no clean trigger when a stock split lands.
**Decision.** Deferred with a design-level veto. There is no "completed" state in the system by design. `fold()` is a totalSupply bookkeeping detail, not a completion signal — emitting a completion event from fold would conflate the two concepts and fire on the first post-effectiveTime transfer rather than at effectiveTime itself. Consumers that need to react to a split landing must compare `effectiveTime` against observed block timestamps on their side. (See memory: "st0x corporate actions — no 'completed' state by design".)

### Item 6 (MEDIUM) — Sync spec/plan docs with as-built
**Concern.** `CORPORATE-ACTIONS-SPEC.md` / `CORPORATE-ACTIONS-PLAN.md` (PR #16 branch) described a SCHEDULED/COMPLETE status enum, a global version counter, and completion-time-assigned monotonic IDs — none of which exist in the as-built system. Leaving the original in place will mislead future readers.
**Decision.** Rewrite both docs in place on PR #16's branch (`feat/corporate-actions-diamond-spec`). Git history preserves the pre-implementation version. Do not reintroduce any "completed" state framing.
**Target PR.** #16 (standalone off main, not in the gt stack).

### Item 7 (MEDIUM) — `LibRebase` header comment worked example
**Concern.** `LibRebase.sol` header comment reads `100 × (1/3) × 3 × (1/3) × 3 = 96`. The correct sequential-rasterize answer is `99` (100→33→99→33→99). This is the load-bearing conceptual example of the whole rebase design and must be arithmetically correct.
**Decision.** Rewrite the header comment with the full worked example showing each multiplication and truncation step. Fix `= 96` to `= 99`. Preserve the "dormant and active accounts converge" framing.
**Target PR.** #21 (pr4-rebase).

### Item 8 (MEDIUM) — Invariant test harness
**Concern.** Strong unit and reference-implementation fuzz tests exist, but no Foundry stateful invariant harness. For a system this interacting (list + cursor + pots + rebase), invariant testing is where the highest-value bugs get caught.
**Decision.** Land a single invariant harness file on PR #25 (top of stack, where all pieces are live) with a handler exposing `schedule`/`cancel`/`warp`/`transfer`/`mint`/`burn` to the fuzzer, bounded actors (5) and bounded multipliers ({1/3, 1/2, 2, 3}). Six invariants:
1. List forward/backward walk counts match; no reachable cycle.
2. Adjacent-node time ordering (ties stable).
3. Per-account cursor monotonicity.
4. After any `_update`, touched accounts satisfy `accountMigrationCursor == totalSupplyLatestSplit`.
5. `sum_over_holders(balanceOf) ≤ totalSupply()` with bounded gap.
6. `totalSupplyLatestSplit` is the latest past-effectiveTime split seen by last `fold()`.
**Target PR.** #25 (pr6-external-interface). Extended on PR #7 to cover receipt-side invariants.

### Item 9 (MEDIUM) — Pin ERC-7201 slot literals
**Concern.** Hard-coded storage slot constants must be pinned against their namespace-derived formulas so that a rename of the namespace string doesn't silently corrupt storage.

**Part A: corp-action slot (`rain.storage.corporate-action.1`) — ALREADY COVERED.**
At apply-time, verified that `test/src/concrete/StoxCorporateActionsFacet.t.sol::testStorageSlotCalculation` (lines 114-118, already in PR #18) does exactly this: re-derives the slot from the namespace string and asserts equality. No change needed.

**Part B: ERC20 slot (`openzeppelin.storage.ERC20`) — TO APPLY.**
At apply-time, read `test/src/lib/LibERC20Storage.t.sol` first; sharpen if present but not best-in-class, add if absent.
**Target PR.** #21 (pr4-rebase) — `LibERC20Storage` is introduced there.

### Item 10 (MEDIUM) — `DO NOT REORDER, APPEND ONLY` on `CorporateActionStorage` + layout pin test
**Concern.** The struct is behind a beacon-proxy-upgradeable vault; a field reorder would silently remap state on upgrade. Today nothing enforces or even documents the append-only invariant.
**Decision.** Add a header comment on the struct stating "DO NOT REORDER. APPEND ONLY." with the reason (ERC-7201 namespaced storage, upgradeable vault, field offsets are positional). Add a storage-layout pin test that writes sentinel values to each field via `LibCorporateAction.getStorage()`, then reads each raw slot at `CORPORATE_ACTION_STORAGE_LOCATION + offset` via `vm.load`, asserting each sentinel lands at its expected offset. ~40 LOC test.
**Target PR adjustment.** Originally planned for PR #18. Moved to **PR #22 (pr2-linked-list)** because at PR #18 the struct has only a `_placeholder uint256` field which PR #22 tears down and replaces with the real fields (`head`, `tail`, `nodes`). The DO-NOT-REORDER invariant becomes live from PR #22 onward. PR #18's placeholder is disposable and doesn't need the comment. The layout pin test will need to be extended in each subsequent PR that appends fields (#21, #24).

### Item 11 (MEDIUM) — Commit slither diagrams — **DEFERRED**
**Decision.** Revisit at external-audit prep time. Not load-bearing for code quality; only useful for an auditor handoff that isn't imminent.

### Item 12 (LOW) — Extract backward-walk insertion in `LibCorporateAction.schedule`
**Concern.** `schedule` mixes sentinel init + node alloc + ordered insertion. Extraction would let the insertion walk be tested directly.
**Decision.** Extract as private `_insertOrdered(CorporateActionStorage storage s, uint256 newIndex, uint64 effectiveTime)`. `schedule` retains sentinel push and node allocation.
**Target PR.** #22 (pr2-linked-list).

### Item 13 (LOW) — Safety comment on `int256(1e18)` cast in `LibStockSplit`
**Decision.** Add a one-line comment above the `forge-lint: disable-next-line(unsafe-typecast)` directive explaining the cast is safe because `1e18` is a compile-time constant.
**Target PR.** #23 (pr3-action-types).

### Item 14 (LOW) — `cancel` comment on orphan nodes and double-cancel guard
**Concern.** Cancelled nodes leave `actionType` / `parameters` stale in `s.nodes`. More importantly, `cancel` sets `effectiveTime = 0` at the end as the double-cancel guard — removing that zero would cause a second cancel of the same index to silently corrupt `head`/`tail`. Currently nothing documents why `effectiveTime = 0` is load-bearing.
**Decision.** Comment on `cancel` documenting (a) orphan nodes remain in `s.nodes` with stale type/parameters but are unreachable via traversal and detectable as `effectiveTime == 0`, and (b) **the `effectiveTime = 0` assignment is the double-cancel guard and must not be removed**. Verify a double-cancel-reverts test exists; if not, add one.
**Target PR.** #22 (pr2-linked-list).
**Discussion.** User initially proposed removing the zeroing entirely (treating cancel as pure unlink). Reviewer walked through the double-cancel path showing `s.head` / `s.tail` would be blown away by a re-cancel without the sentinel, and user concurred.

### Item 15 (LOW) — Index `toCursor` on `AccountMigrated` — **DEFERRED**
**Decision.** No concrete downstream consumer has asked for the topic filter. Event data is complete; client-side filtering is cheap at this event volume.

### Item 16 (LOW) — `CLAUDE.md` "Breaking dependency bumps" section
**Concern.** OZ `ERC20Upgradeable` v5's ERC-7201 slot and `rain.math.float`'s precision characteristics are both pinned by assumptions in the stack. A routine submodule bump could silently break things.
**Decision.** Add a "Breaking dependency bumps" subsection under `CLAUDE.md` §Dependencies with two entries: OZ (pin, failure mode, re-verify steps — re-derive `ERC20_STORAGE_LOCATION`, re-run runtime invariant test) and rain.math.float (pin, failure mode — changes to rounding/saturation; re-verify steps — re-review `LibStockSplit` bounds and re-run the `effectiveTotalSupply` reference-implementation fuzz).
**Target PR.** #25 (top of stack).

## Apply Order

Downstack-to-upstack so each PR's restack upward is a clean propagation:

1. **PR #16** (standalone off main) — Item 6. ✓ done (commit `3cde164`).
2. **PR #18** — audit record doc (this file) + Item 3. (Item 9-corp-slot no-op; Item 10 moved to PR #22.)
3. **PR #22** — Items 10, 12, 14.
4. **PR #23** — Item 13.
5. **PR #21** — Items 7, 9-erc20.
6. **PR #24** — Item 1.
7. **PR #25** — Items 8, 16.
8. **Pause** — draft PR #7 sub-plan for receipt coordination (Item 2), hand to user for sign-off, then implement.

Each PR is committed with a commit message referencing the specific item number(s) for traceability.

## Deferred follow-ups

- Item 4 (list length cap) — revisit if the scheduler ever moves off a multi-sig trust model.
- Item 5 (completion event) — permanently rejected by design.
- Item 11 (slither diagrams) — revisit at external-audit prep.
- Item 15 (indexed `toCursor`) — revisit if an indexer team asks.
