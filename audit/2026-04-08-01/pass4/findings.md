# Pass 4 — Code Quality Review

## Toolchain status (this run)

- `forge fmt --check` → **clean, exit 0**. A_FMT-1 from 2026-04-07-01 is resolved.
- `forge build` → **0 warnings, 0 errors**. A26-P4-1 / A28-P4-1 (`unsafe-typecast` misplacement) are resolved — `forge-lint` no longer emits those warnings.
- `forge build` → **24 forge-lint `notes`** (21 `unused-import`, 2 `unsafe-cheatcode`, 1 `screaming-snake-case-immutable`). Notes sit below "warning" severity in forge-lint's hierarchy and did not exist as a category in the prior audit; they are new signal surfaced by a forge-lint upgrade. Treated as LOW per the skill rule "no warnings from the project's build toolchain — build warnings are real problems (LOW or higher)" — notes are close enough to warrant LOW unless the project explicitly opts out of them.

## Status of prior-run findings (2026-04-07-01)

- **A26-P4-1 (LOW)** — `LibRebase.sol` `forge-lint: disable-next-line` misplaced: **FIXED** on PR4 (`62d10f6 fix(audit): lint disable placement`).
- **A28-P4-1 (LOW)** — `LibTotalSupply.sol` same pattern: **FIXED** on PR5 (same commit).
- **A_FMT-1 (LOW)** — forge fmt diffs: **FIXED** on PR2 (`4447bcb fix(audit): forge fmt + head/tail NatSpec`).
- **A21-P4-1 (INFO)** — storage struct ownership mixed with LibTotalSupply: still INFO, no change; will remain deferred as INFO this run.
- **A21-P4-2 (INFO)** — schedule O(n) walk: same as Pass 1 P1-2.
- **A01-P4-1 (INFO)** — four near-identical traversal wrappers on the facet: still INFO, no change.

## New findings (this run)

### P4-1 — Unused `Float` import in `StoxReceiptVault.t.sol`

**Severity:** LOW

**Location:** `test/src/concrete/StoxReceiptVault.t.sol:6`

```solidity
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
```

`Float` is not referenced in the file (the `_splitParams` helper uses `LibDecimalFloat.packLossless` which returns a `Float` but the name is never explicitly typed). `forge-lint` note:

```
note[unused-import]: unused imports should be removed
 --> test/src/concrete/StoxReceiptVault.t.sol:6:9
```

**PR attribution:** **PR4 (#21)** — the file was enriched with the migration integration tests on PR4.

**Proposed fix:** `.fixes/P4-1.md`.

### P4-2 — Unused `Float` import in `StoxCorporateActionsFacet.t.sol`

**Severity:** LOW

**Location:** `test/src/concrete/StoxCorporateActionsFacet.t.sol:19`

```solidity
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
```

Same pattern — `Float` is unused; the facet tests call `LibDecimalFloat.packLossless` without naming the return type.

**PR attribution:** **PR1 (#18)** — the facet test file was born on PR1.

**Proposed fix:** `.fixes/P4-2.md`.

### P4-3 — `DelegatecallHarness.facet` immutable should be SCREAMING_SNAKE_CASE

**Severity:** LOW

**Location:** `test/src/concrete/StoxCorporateActionsFacet.t.sol:57`

```solidity
address public immutable facet;
```

`forge-lint` note:

```
note[screaming-snake-case-immutable]: immutables should use SCREAMING_SNAKE_CASE
  --> test/src/concrete/StoxCorporateActionsFacet.t.sol:57:30
   |
57 |     address public immutable facet;
   |                              ^^^^^ help: consider using: `FACET`
```

Rename `facet` → `FACET` and update the one constructor assignment + the one fallback `address target = facet;` reference.

**PR attribution:** **PR1 (#18)**.

**Proposed fix:** `.fixes/P4-3.md`.

### P4-4 — `LibERC20Storage.setTotalSupply` is dead code in src/

**Severity:** LOW

**Location:** `src/lib/LibERC20Storage.sol:54-58`

The function is declared and documented but **not called anywhere in `src/`**. The only call sites are in the test harness (`test/src/lib/LibERC20Storage.t.sol` — `TestERC20.libSetTotalSupply`), which does not reach production code paths. The production rebase flow never writes OZ's `_totalSupply` directly — `LibTotalSupply` tracks supply via per-cursor pots, and `super._update` is the only path that mutates OZ's raw `_totalSupply`.

This matters because `setTotalSupply` is a "sharp-edged" helper: it writes directly into OZ ERC20 storage, bypassing every invariant. A future refactor that mistakenly calls it would silently desynchronize the per-cursor pot accounting.

**Disposition options:**
1. Remove `setTotalSupply` entirely and update the test file to drop `libSetTotalSupply` (which becomes dead too).
2. Keep it but add a `@dev` WARNING block explicitly stating that production code must NEVER call it (the pot model owns totalSupply), and move the test-only helper into the test file's harness contract rather than the library.

Option 1 is the cleaner cut. Nothing in the current code path needs it.

**PR attribution:** **PR4 (#21)** — `feat/corporate-actions-pr4-rebase`, where `LibERC20Storage` was introduced.

**Proposed fix:** `.fixes/P4-4.md`.

### P4-5 — `LibStockSplit.encodeParameters` is dead code in src/

**Severity:** LOW

**Location:** `src/lib/LibStockSplit.sol:25-27`

```solidity
function encodeParameters(Float multiplier) internal pure returns (bytes memory) {
    return abi.encode(multiplier);
}
```

Not called from `src/`. Only referenced in `test/src/lib/LibStockSplit.t.sol::testEncodeDecodeRoundtrip`. Production code always `abi.encode(multiplier)` inline (e.g. the scheduler test helpers in `StoxReceiptVault.t.sol::_splitParams`).

**Disposition options:**
1. Remove `encodeParameters` and update the round-trip test to use `abi.encode` directly (losing nothing — the "round-trip" now just tests `decodeParameters(abi.encode(m)) == m`, which is essentially tautological on a single abi.encode of a value type).
2. Keep it as the canonical entry point and route all callers (tests + any future external helper) through it.

Option 1 is more honest; option 2 requires additional refactoring and gains little.

**PR attribution:** **PR3 (#23)**.

**Proposed fix:** `.fixes/P4-5.md`.

### P4-6 — `LibCorporateAction` accessors `head()` / `tail()` / `headNode()` / `tailNode()` are dead code in src/

**Severity:** INFO

**Location:** `src/lib/LibCorporateAction.sol:197-222`

None of the four accessors are called from anywhere in `src/`. The facet reaches the list via `LibCorporateActionNode.nextOfType(0, ...)` and `prevOfType(0, ...)` which internally use `s.head` / `s.tail` directly. Tests call them via `LibHarness`.

Under the same "dead-code in production library" framing as P4-4 / P4-5, these accessors could be deleted without impacting production behavior and moved into the test harness. Holding at INFO (rather than LOW) because:
- They fit a documented API pattern on `LibCorporateAction` — removing them shrinks the library surface for external consumers who might want to build their own facet methods on top.
- The head/tail values themselves are genuinely useful — the question is only whether the accessors belong in the production library or in the test harness.

No fix file; triage decides whether to remove or keep.

**PR attribution:** **PR2 (#22)**.

### P4-7 — Pre-existing forge-lint notes in non-stack test files (bulk)

**Severity:** LOW (aggregated; individual items are note-level)

**Locations (all in `test/` directory, not source-scope for the corporate-actions stack):**

| File | Count | Notes |
|---|---|---|
| `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` | 9 | `unused-import` |
| `test/src/concrete/deploy/StoxUnifiedDeployer.t.sol` | 6 | `unused-import` |
| `test/src/concrete/StoxWrappedTokenVault.t.sol` | 2 | `unused-import` |
| `test/src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.t.sol` | 2 | `unused-import` |
| `test/src/concrete/StoxWrappedTokenVaultV2.t.sol` | 1 | `unused-import` |
| `test/script/Deploy.t.sol` | 2 | `unsafe-cheatcode` (`vm.setEnv`) |

These files are **not modified** by the corporate-actions stack. They predate the stack's base. The notes are either:
- A new forge-lint rule that was added after the last audit run and now surfaces older code, OR
- Pre-existing notes that the prior audit's skill invocation didn't enumerate (it focused on `unsafe-typecast` warnings).

**Disposition:**
- **Not attributed to any stack PR.** Fixes land on `main` as a separate cleanup PR, or on an early stack PR as a prepared commit if the user wants the stack to leave the tree in a lint-clean state.
- The `unsafe-cheatcode` notes for `vm.setEnv` in `Deploy.t.sol` are intentional (env-var driven deployment suite test) and would need `forge-lint: disable-line(unsafe-cheatcode)` with a rationale comment rather than removal.

**Proposed fix:** `.fixes/P4-7.md` — bulk import pruning + cheatcode suppression with rationale.

**Note to user:** since these are out-of-stack and the stack is what's being audited here, I recommend landing the fix as a separate PR (or at the base of the stack on a "lint cleanup" commit) rather than distributing them across the six stack branches. This keeps each stack PR scoped to its conceptual unit.

## Items deliberately not flagged

- `A21-P4-1` (storage struct ownership) — still INFO, still the cleanest option (Option 2: doc) is already captured in the prior Pass 3 finding A21-P3-2. No new action.
- `A01-P4-1` (near-identical facet wrappers) — still INFO. Four getters × 8 lines each = 32 lines of bearable duplication.
- `A21-P4-2` / `schedule()` O(n) walk — same as Pass 1 P1-2, still INFO.

## Files carried forward by reference

Non-stack source files have no change in Pass 4 posture since `audit/2026-03-19-01/pass4/`. No open findings from that run.
