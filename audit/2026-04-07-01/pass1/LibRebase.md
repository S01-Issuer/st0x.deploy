# A26 — Pass 1 (Security): LibRebase

**File:** `src/lib/LibRebase.sol` (70 lines)

## Evidence of thorough reading

**Library:** `LibRebase`

**Functions:**
- `migratedBalance(uint256, uint256)` internal view — line 31

## Findings

### A26-1 — CRITICAL (root cause): zero-balance early return leaves the cursor unadvanced, enabling A03-1's mint/transfer over-multiplication

**Severity:** CRITICAL (root cause, paired with A03-1)

**Location:** `src/lib/LibRebase.sol:36-40`

```solidity
newCursor = cursor;

if (storedBalance == 0) {
    return (storedBalance, newCursor);
}
```

This early return is the root cause of A03-1. For a zero-balance account with completed splits ahead of its cursor, `migratedBalance` returns the *input* cursor unchanged. `StoxReceiptVault._migrateAccount` then short-circuits via the `newCursor == currentCursor` check at vault line 68, so the account's stored cursor is never advanced. After a subsequent `super._update` writes a non-zero stored balance (mint to fresh account, or transfer-in to fresh recipient), that balance lives at cursor 0 in the eyes of the migration system, even though semantically it is at the post-rebase basis. The next migration walks the splits from cursor 0 and re-applies every multiplier, returning a balance inflated by the cumulative split product.

See `pass1/StoxReceiptVault.md` (A03-1) for the full reproduction, impact analysis, and PR attribution. The fix lives in this file (LibRebase) primarily, with a paired adjustment in StoxReceiptVault.

**Why this is in PR4 attribution:** the early return was added together with the rest of `migratedBalance` in commit `9514222`/`235ee7c` on `feat/corporate-actions-pr4-rebase`. The same PR introduced both `LibRebase` and the `_migrateAccount` shortcut.

**Why the test enshrined the bug:** `test/src/lib/LibRebase.t.sol:42-48` (`testZeroBalanceUnchanged`) explicitly asserts `cursor == 0` after migration of a zero balance with a 2x completed split. This test must be **changed to assert `cursor == 1`** after the fix. The test name and intent are correct ("zero balance stays zero") but the cursor assertion was wrong from the start. The library-level harness test was written without the integration view that would have surfaced the consequence at the vault layer.

**Proposed fix:** see `.fixes/A26-1.md` (paired with `.fixes/A03-1.md`). Two implementation options are presented; the recommended one rewrites the zero-balance branch in `migratedBalance` to walk the linked list and return the latest completed split index (without applying multipliers, since 0 × anything = 0).

### A26-2 — `int256(balance)` cast is unguarded for `balance > 2**255 - 1`

**Severity:** INFO

**Location:** `src/lib/LibRebase.sol:57` (also `LibTotalSupply.sol:96`)

```solidity
LibDecimalFloat.packLossless(int256(balance), 0)
```

The cast wraps for `balance` exceeding `type(int256).max`. ERC20 balances bounded by `type(uint256).max` are well in excess of the `int256` ceiling, but in practice no realistic stock supply approaches `2**255`. The `forge-lint: disable-next-line(unsafe-typecast)` annotation acknowledges the choice. INFO; no action required, but documenting the rationale alongside the disable directive (rather than just suppressing) would aid future readers.

## Items deliberately not flagged

- Sequential rasterization (one truncation per multiplier) is intentional and documented at lines 14-20. Verified the loop matches the description.
- View-only function: no reentrancy concerns, no external calls beyond the pure rain.math.float library calls.
- The `modified` flag and the `if (!modified) return (storedBalance, cursor);` exit path correctly handle the case where the input cursor is already past all completed splits (returns the original cursor, not a stale `newCursor` from before the loop).
