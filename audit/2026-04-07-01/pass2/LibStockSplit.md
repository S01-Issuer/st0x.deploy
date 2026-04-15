# A27 — Pass 2 (Test Coverage): LibStockSplit

**Source:** `src/lib/LibStockSplit.sol`
**Tests:** `test/src/lib/LibStockSplit.t.sol` (129 lines)

## Coverage observed

- `LibStockSplitValidationTest`
  - `testValidMultiplier` — 2x multiplier validates
  - `testZeroMultiplierReverts` — `coefficient == 0` reverts
  - `testFractionalMultiplierValid` — 1/3 validates
  - `testEncodeDecodeRoundtrip` — round trip preserves the Float
- `LibStockSplitResolveTest`
  - `testResolveStockSplit` / `testResolveStockSplitZeroMultiplierReverts` / `testResolveUnknownTypeReverts`
- `LibStockSplitLifecycleTest`
  - `testStockSplitLifecycle` — schedule → warp → countCompleted → nextOfType → decode

## Findings

### A27-P2-1 — Negative-coefficient multiplier path (`coefficient < 0`) is not tested

**Severity:** LOW

**Location:** `src/lib/LibStockSplit.sol:19`

```solidity
if (coefficient <= 0) revert InvalidSplitMultiplier();
```

The test only covers `coefficient == 0`. The `< 0` branch is unreached. Adding a test with a negative-coefficient `Float` exercises the full revert condition.

**Suggested fix:** see `.fixes/A27-P2-1.md`.

### A27-P2-2 — No test for near-zero / extremely large multipliers (paired with A27-1)

**Severity:** LOW

**Location:** Validation has no upper or lower bound on the float magnitude.

Tests assert that `coefficient > 0` is sufficient validation. They never construct a multiplier like `1e-30` or `1e30` to verify that downstream `LibRebase.migratedBalance` produces a sane result, or that validation rejects it. After A27-1's bound is added, this test should be the regression guard for that bound.

**Suggested fix:** see `.fixes/A27-P2-2.md` (depends on A27-1's chosen bound).
