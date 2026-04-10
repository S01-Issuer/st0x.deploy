# A26 — Pass 2 (Test Coverage): LibRebase

**Source:** `src/lib/LibRebase.sol`
**Tests:** `test/src/lib/LibRebase.t.sol` (139 lines)

## Coverage observed

- `testZeroBalanceUnchanged` — **enshrines the buggy behavior; see A26-P2-1 below**
- `testNoCompletedSplits` — pending-only list, balance unchanged, cursor unchanged
- `testSimpleTwoXSplit` — basic 2x
- `testOneThirdReverseSplit` — basic 1/3 with truncation
- `testSequentialPrecision` — 1/3 → 3 → 1/3 → 3 = 96 (not 100)
- `testMultipleSplitsSequential` — 2x then 3x
- `testPartialMigration` — cursor at the first split, walks only the second
- `testAlreadyMigrated` — cursor past all completed splits, returns unchanged
- `testFuzzTwoXSplit` — fuzz balance with 2x
- `testFuzzSequentialTwoX` — fuzz balance and split count

## Findings

### A26-P2-1 — CRITICAL: `testZeroBalanceUnchanged` enshrines the A03-1 bug as "correct" behavior. The test must be rewritten to assert that the cursor *advances* through completed splits.

**Severity:** CRITICAL (test asserts buggy behavior; co-requirement of fixing A03-1 / A26-1)

**Location:** `test/src/lib/LibRebase.t.sol:42-48`

```solidity
/// Zero balance stays zero regardless of multipliers.
function testZeroBalanceUnchanged() external {
    h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
    vm.warp(2000);
    (uint256 balance, uint256 cursor) = h.migratedBalance(0, 0);
    assertEq(balance, 0);
    assertEq(cursor, 0);   // ← WRONG. Should assert cursor == 1.
}
```

The test name and the `balance == 0` assertion are correct: zero balances always remain zero (anything multiplied by zero is zero). But the cursor assertion is wrong: when there are completed splits ahead of the cursor, the cursor must advance to reflect that this account is now at the post-rebase basis. Otherwise, the next time the account's stored balance becomes non-zero (mint, transfer-in), subsequent reads will erroneously re-apply the splits.

**Required change** (paired with the code fix in `.fixes/A26-1.md`):

```solidity
/// Zero balance stays zero, but the cursor advances to the latest completed split.
/// Otherwise a subsequent mint/transfer to this account would interpret the new
/// balance as pre-rebase and re-apply the multiplier.
function testZeroBalanceAdvancesCursor() external {
    h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
    vm.warp(2000);
    (uint256 balance, uint256 cursor) = h.migratedBalance(0, 0);
    assertEq(balance, 0);
    assertEq(cursor, 1);   // ← Cursor must advance to the completed split.
}

/// Two completed splits ahead → cursor advances to the latest.
function testZeroBalanceAdvancesAcrossMultipleCompletedSplits() external {
    h.schedule(ACTION_TYPE_STOCK_SPLIT, 1500, _splitParams(2));
    h.schedule(ACTION_TYPE_STOCK_SPLIT, 2500, _splitParams(3));
    vm.warp(3000);
    (uint256 balance, uint256 cursor) = h.migratedBalance(0, 0);
    assertEq(balance, 0);
    assertEq(cursor, 2);
}

/// Pending splits do not advance the cursor (we only walk completed ones).
function testZeroBalancePendingSplitDoesNotAdvanceCursor() external {
    h.schedule(ACTION_TYPE_STOCK_SPLIT, 5000, _splitParams(2));
    (uint256 balance, uint256 cursor) = h.migratedBalance(0, 0);
    assertEq(balance, 0);
    assertEq(cursor, 0);
}
```

**Suggested fix:** see `.fixes/A26-P2-1.md` (paired with the code fix `.fixes/A26-1.md`). The fix lands on PR4.

### A26-P2-2 — No test for `migratedBalance` walking past non-stock-split nodes interspersed with stock splits

**Severity:** LOW

**Location:** `src/lib/LibRebase.sol:44` (uses `ACTION_TYPE_STOCK_SPLIT` mask)

Today only stock splits exist, so the mask filter never has anything else to skip. But `LibRebase.migratedBalance` calls `LibCorporateActionNode.nextOfType(_, ACTION_TYPE_STOCK_SPLIT, COMPLETED)` — if a future PR adds a different action type (e.g. dividend) that lives in the same linked list but should not affect rebases, the mask is the only thing preventing the rebase walk from incorrectly applying it. There is no test asserting that a non-split node interspersed in the list is correctly skipped.

**Suggested fix:** see `.fixes/A26-P2-2.md`. Adds a test that schedules a fake non-split action type (e.g., `1 << 1`) between two stock splits and asserts the rebase result matches just the two stock splits.

## Items not flagged

- The fuzz test `testFuzzSequentialTwoX` covers up to 5 sequential 2x splits and uses `bound`/`vm.assume` correctly.
- `testSequentialPrecision` correctly verifies the 96-not-100 outcome of 1/3 → 3 → 1/3 → 3 on a stored balance of 100.
- The harness wraps `LibRebase.migratedBalance` faithfully — no harness drift.
