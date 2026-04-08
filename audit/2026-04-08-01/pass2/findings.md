# Pass 2 — Test Coverage Review

Scope: for each stack-modified source file, read source + corresponding test file(s) and record coverage gaps. Unchanged source files carried forward by reference.

## Files reviewed

| Source | Test |
|---|---|
| `src/concrete/StoxCorporateActionsFacet.sol` | `test/src/concrete/StoxCorporateActionsFacet.t.sol` (585 lines) |
| `src/concrete/StoxReceiptVault.sol` | `test/src/concrete/StoxReceiptVault.t.sol` (272 lines) |
| `src/interface/ICorporateActionsV1.sol` | (pure interface, no executable surface) |
| `src/lib/LibCorporateAction.sol` | via `LibHarness` in `StoxCorporateActionsFacet.t.sol` + `LibStockSplit.t.sol::StockSplitHarness` |
| `src/lib/LibCorporateActionNode.sol` | via `LibHarness` in `StoxCorporateActionsFacet.t.sol` + facet-level getters |
| `src/lib/LibERC20Storage.sol` | `test/src/lib/LibERC20Storage.t.sol` (129 lines) |
| `src/lib/LibRebase.sol` | `test/src/lib/LibRebase.t.sol` (169 lines) |
| `src/lib/LibStockSplit.sol` | `test/src/lib/LibStockSplit.t.sol` (129 lines) |
| `src/lib/LibTotalSupply.sol` | `test/src/lib/LibTotalSupply.t.sol` (339 lines) |

## Status of prior-run findings (2026-04-07-01)

- **A03-P2-1 (HIGH)** — vault-level integration tests for corporate-actions hooks: **FIXED** on PR4 (`62d10f6`, `57ecc0d`) + PR5 integration additions. `StoxReceiptVaultMigrationIntegrationTest` exists with all eight proposed regression tests (A–H) wired through a `TestStoxReceiptVault` bypass.
- **A28-P2-1 (HIGH)** — LibTotalSupply ∘ vault integration: **FIXED** as a consequence of A03-P2-1's fix.
- **A26-P2-1 (CRITICAL)** — `testZeroBalanceUnchanged` encodes wrong cursor: **FIXED**. `test/src/lib/LibRebase.t.sol:46-52` now asserts `cursor == 1` after migration of a zero balance with a 2x completed split, with two additional regression tests for multi-split and pending-only cases.
- **A01-P2-1 (LOW)** — facet auth path via `scheduleCorporateAction` / `cancelCorporateAction`: **FIXED** on PR1 (`66e917a`). A `MockAuthorizer` records calls and tests assert per-action data forwarding + deny-mode revert propagation.
- **A01-P2-3 (LOW)** — facet traversal getters (`latestActionOfType` / `earliestActionOfType` / `nextOfType` / `prevOfType`) exercised via facet wrapper: **FIXED** on PR6 (`4c2b7eb`). `testFacetTraversalGettersFilterParameter` covers all four getters × all three filters end-to-end through the delegatecall harness.
- **A01-P2-4 (LOW)** — `prevOfType` filter coverage: **FIXED** as part of the same facet-level test.
- **A21-P2-1 (LOW)** — tied effective-time ordering: **FIXED** on PR2 (`e241af5`). Two dedicated tests assert stable insertion at the back of the equal-time run.
- **A22-P2-1 (LOW)** — `prevOfType` COMPLETED / PENDING branches: **FIXED** via the facet traversal test.
- **A23-P2-1 (LOW)** — `LibERC20Storage` OZ drift invariant: **FIXED** on PR4 (`57ecc0d`). `test/src/lib/LibERC20Storage.t.sol` exercises OZ `_mint` → `libBalanceOf` equality and the reciprocal `libSetBalance` → OZ `balanceOf` roundtrip.
- **A28-P2-3 (INFO)** — fuzz `effectiveTotalSupply` vs reference: **FIXED** on PR5 (`c8bdff5`). `testFuzzEffectiveTotalSupplyMatchesReference` compares the production accumulator against an in-test pure-Solidity reference.

## Outstanding from prior run

- **A27-P2-1 (LOW)** — negative-coefficient multiplier rejection: **NOT FIXED**. See P2-1 below.
- **A27-P2-2 (LOW)** — near-zero / near-saturation multiplier tests: **NOT FIXED**. Tied to Pass 1 P1-1 (same file, bound implementation). Bundled into P2-2 below.
- **A28-P2-2 (LOW)** — `onBurn` underflow-revert protection: **NOT FIXED**. See P2-3 below.
- **A01-P2-2 (LOW)** — `CorporateActionScheduled` / `CorporateActionCancelled` event-emission assertions: **NOT FIXED**. No `vm.expectEmit` for these events anywhere in the facet test file (verified via grep: `CorporateActionScheduled|CorporateActionCancelled|expectEmit` → 0 matches). See P2-4 below.
- **A26-P2-2 (INFO)** — non-split node interspersed with splits: **still deferred**, no second action type yet. Not re-raised.

## New findings (this run)

### P2-1 — Negative-coefficient multiplier path not exercised

**Severity:** LOW

**Location:** `test/src/lib/LibStockSplit.t.sol:60-63` (`testZeroMultiplierReverts`)

The existing test only covers `coefficient == 0`. The `< 0` branch of `if (coefficient <= 0) revert InvalidSplitMultiplier();` (LibStockSplit.sol:19) is unreached. A regression that flipped `<= 0` to `== 0` would silently accept negative-coefficient floats — which would then propagate through `LibDecimalFloat.mul` and corrupt every rebased balance.

**PR attribution:** **PR3 (#23)**, `feat/corporate-actions-pr3-action-types`.

**Proposed fix:** `.fixes/P2-1.md` — add `testNegativeCoefficientMultiplierReverts`.

### P2-2 — Near-zero and near-saturation multiplier tests (ties P1-1)

**Severity:** LOW

**Location:** `test/src/lib/LibStockSplit.t.sol`

Re-raise of prior A27-P2-2 — still open because the P1-1 bound has not yet been implemented. The fix file `.fixes/P1-1.md` already specifies the tests that land with the bound; this entry is a placeholder in the pass-2 tally so the triage phase doesn't lose track.

**PR attribution:** **PR3 (#23)** — same landing branch as P1-1.

**Proposed fix:** bundled with `.fixes/P1-1.md`.

### P2-3 — `LibTotalSupply.onBurn` underflow-revert protection not tested

**Severity:** LOW

**Location:** `test/src/lib/LibTotalSupply.t.sol` (no underflow-specific test)

The burn-after-fold test at line 198 exercises a normal burn where the pot has enough room. Neither that test nor any other asserts that `onBurn(amount)` reverts via Solidity 0.8 underflow panic when `amount > unmigrated[totalSupplyLatestSplit]`. This invariant is load-bearing: vault-level `_update` guarantees the precondition via per-account migration, but a future refactor that adds an `unchecked` block or re-orders the call sites could silently break it. A harness-level test confirms the revert is the documented behavior.

**PR attribution:** **PR5 (#24)**, `feat/corporate-actions-pr5-total-supply` — where `onBurn` lives.

**Proposed fix:** `.fixes/P2-3.md` — add `testOnBurnUnderflowReverts`.

### P2-4 — `CorporateActionScheduled` / `CorporateActionCancelled` events never asserted

**Severity:** LOW

**Location:** `test/src/concrete/StoxCorporateActionsFacet.t.sol` (no `vm.expectEmit` anywhere in the file)

The facet declares two events (`StoxCorporateActionsFacet.sol:25`, `:32`) that are consumed by offchain indexers and the issuer UI. Their topic hash, indexed-ness, and parameter order are part of the public API, yet no test asserts them — a refactor that accidentally dropped one of the `emit` calls would pass tests.

The event assertions should sit alongside the existing auth-path tests (`testScheduleCorporateActionForwardsContextToAuthorizer` and similar) but with a real scheduler path (use `STOCK_SPLIT_TYPE_HASH` + a valid multiplier so `resolveActionType` succeeds and the state write lands).

**PR attribution:** **PR1 (#18)** — where the events were first declared and where the facet-level test file lives.

**Proposed fix:** `.fixes/P2-4.md` — add `testScheduleCorporateActionEmitsEvent` and `testCancelCorporateActionEmitsEvent`.

## Items deliberately not flagged

- `headNode()` / `tailNode()` accessors on `LibCorporateAction` remain not directly unit-tested. Prior A21-P2-2 was INFO-only; still INFO. They are only ever called from places that have already scheduled at least one node (guaranteeing `s.nodes.length > 0`), so the edge case is unreachable in practice.
- Empty-list fast path of `LibCorporateActionNode.nextOfType(0, _, _)` (prior A22-P2-2) — still INFO; the cancellation-based path already covers the `s.head == 0` case functionally.
- `LibRebase` non-split-interspersed test — still deferred (A26-P2-2). No second action type exists; speculative coverage.

## Files carried forward by reference

Non-stack source files (see pass1/findings.md § "Files carried forward by reference") have unchanged test coverage and no open Pass 2 findings from `audit/2026-03-19-01/pass2/`.
