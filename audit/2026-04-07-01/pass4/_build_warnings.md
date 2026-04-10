# Pass 4 — Build warnings (toolchain output)

`nix develop -c forge build` succeeds but emits **two `unsafe-typecast` warnings** that were intended to be suppressed but are not, because the `forge-lint: disable-next-line` directive is placed one line above the actual cast (the cast is two lines below the directive due to multi-line function-call formatting).

Per the audit skill rule "no warnings from the project's build toolchain — build warnings are real problems (LOW or higher), not INFO", these become two LOW findings.

`nix develop -c forge fmt --check` reports diffs in **5 files**, which is a third LOW finding (style inconsistency / pre-commit format check would fail).

## Findings

### A26-P4-1 — `forge-lint: disable-next-line(unsafe-typecast)` in `LibRebase.sol` does not actually suppress the warning

**Severity:** LOW

**Location:** `src/lib/LibRebase.sol:55-58`

```solidity
// Rasterize after each multiplier to match what storage writes
// would produce. This ensures dormant and active accounts
// converge to identical balances.
// forge-lint: disable-next-line(unsafe-typecast)
(balance,) = LibDecimalFloat.toFixedDecimalLossy(
    LibDecimalFloat.mul(LibDecimalFloat.packLossless(int256(balance), 0), multiplier), 0
);
```

The `disable-next-line` directive applies to the line beginning `(balance,) = LibDecimalFloat.toFixedDecimalLossy(`. The actual `int256(balance)` cast that triggers the lint is on the line **after** that, so the suppression misses. Build output:

```
warning[unsafe-typecast]: typecasts that can truncate values should be checked
   ╭▸ src/lib/LibRebase.sol:57:66
```

**Suggested fix:** see `.fixes/A26-P4-1.md`. Move the disable directive (or rewrite as `forge-lint: disable-line` placed on the cast's actual line), and add the missing rationale comment that the `note:` from forge-lint requested.

**PR attribution:** PR4 (`feat/corporate-actions-pr4-rebase`).

### A28-P4-1 — Same `unsafe-typecast` suppression bug in `LibTotalSupply.sol`

**Severity:** LOW

**Location:** `src/lib/LibTotalSupply.sol:94-97`

Identical pattern: directive on line 94, cast on line 96. Build emits:

```
warning[unsafe-typecast]: typecasts that can truncate values should be checked
   ╭▸ src/lib/LibTotalSupply.sol:96:66
```

**Suggested fix:** see `.fixes/A28-P4-1.md`.

**PR attribution:** PR5 (`feat/corporate-actions-pr5-total-supply`).

### A_FMT-1 — `forge fmt` reports diffs in 5 files

**Severity:** LOW

**Files needing format:**
- `src/lib/LibCorporateAction.sol`
- `src/lib/LibCorporateActionNode.sol`
- `src/lib/LibRebase.sol`
- `src/lib/LibTotalSupply.sol`
- `test/src/concrete/StoxCorporateActionsFacet.t.sol`

The diffs are minor (line-wrap of multi-import statements and one wide function signature), but `rainix-sol-static` will fail on these.

**Suggested fix:** see `.fixes/A_FMT-1.md` — single command `nix develop -c forge fmt` applied per PR, with each PR's restack picking up the formatting for the file it owns:
- `LibCorporateAction.sol`, `LibCorporateActionNode.sol` → PR2 (`feat/corporate-actions-pr2-linked-list`)
- `LibRebase.sol` → PR4
- `LibTotalSupply.sol` → PR5
- `test/src/concrete/StoxCorporateActionsFacet.t.sol` → PR1 (the test file is born in PR1's facet shell)
