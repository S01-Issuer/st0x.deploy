# A03 — Pass 2 (Test Coverage): StoxReceiptVault

**Source:** `src/concrete/StoxReceiptVault.sol` (79 lines)
**Tests:** `test/src/concrete/StoxReceiptVault.t.sol` (16 lines, 1 test)

## What is covered

A single test:

- `testConstructorDisablesInitializers` — verifies the implementation contract is initialized-locked at construction.

## Findings

### A03-P2-1 — HIGH: No integration tests for any of the corporate-actions hooks added to StoxReceiptVault. This is the test gap that hides the CRITICAL A03-1 inflation bug.

**Severity:** HIGH

**Location:** `test/src/concrete/StoxReceiptVault.t.sol` (entire file)

The corporate-actions stack added four new override / new functions to `StoxReceiptVault`:

| Source line | Function | Test? |
|---|---|---|
| `30` | `balanceOf(address)` override | ❌ |
| `38` | `totalSupply()` override | ❌ |
| `44` | `_update(address, address, uint256)` override (mint/burn/transfer + migration) | ❌ |
| `59` | `_migrateAccount(address)` private helper | ❌ |

None of them are tested at the vault layer. The library-layer tests for `LibRebase`, `LibTotalSupply`, and the corporate action linked list exercise the math but never compose with a real `OffchainAssetReceiptVault` going through `super._update`. The composition is exactly where A03-1 manifests:

1. `LibRebase.migratedBalance(0, 0)` returns `(0, 0)` — tested as "correct" by `testZeroBalanceUnchanged`.
2. `_migrateAccount` short-circuits for fresh accounts — never tested.
3. `super._update` writes a non-zero stored balance to the fresh account — never composed.
4. The next read of `balanceOf` over-multiplies — never asserted to be correct.

The result is a HIGH severity coverage gap because A03-1 is CRITICAL and the missing tests are the *only* thing that would have caught it before merge.

**Required tests** (each must use a real `StoxReceiptVault` instance, not a harness):

A. **`testBalanceOfBeforeAnySplit`** — mint to alice, no splits scheduled, `balanceOf(alice)` returns mint amount.
B. **`testTotalSupplyBeforeAnySplit`** — same but checks `totalSupply()`.
C. **`testBalanceOfAfterCompletedSplitForExistingHolder`** — alice already has a balance, split completes, `balanceOf(alice)` returns the rebased amount, then alice does an interaction (e.g., transfer 0 to herself or transfer 1 wei to bob) and her stored balance / cursor advance correctly.
D. **`testMintToFreshAccountAfterCompletedSplitDoesNotInflate`** — A03-1 reproduction. Setup: pre-mint some supply to bob, schedule a 2x split, warp past effectiveTime, mint 100 to alice (fresh). Assert `balanceOf(alice) == 100`. **This test currently fails on the buggy code and passes on the fixed code.**
E. **`testTransferToFreshRecipientAfterCompletedSplitDoesNotInflate`** — A03-1 transfer reproduction. Setup as above but instead of minting, alice (a holder migrated through the split) transfers 100 to bob (fresh). Assert `balanceOf(bob) == 100` and `balanceOf(alice)` decreased by exactly 100.
F. **`testBalanceOfTotalSupplyConsistencyAfterMixedActivity`** — fuzz over a sequence of mints/burns/transfers/splits and assert `sum(balanceOf(holders)) == totalSupply()` at every step. This is the invariant A28-1 says is currently broken.
G. **`testAccountMigratedEventEmittedOnMigration`** — assert `AccountMigrated(account, fromCursor, toCursor, oldBalance, newBalance)` is emitted with correct values when an account that has a non-zero stored balance and a stale cursor is touched.
H. **`testFreshAccountCursorAdvancesOnZeroBalanceMigration`** — direct test of the fix: a fresh account, after `_migrateAccount` has run (e.g., via a 0-amount transfer to it), has its `accountMigrationCursor` set to `totalSupplyLatestSplit` (or equivalent latest cursor).

**Suggested fix:** see `.fixes/A03-P2-1.md`. The proposal includes test scaffolding for instantiating a real `StoxReceiptVault` (with a minimal mock authorizer / receipt) and the eight tests above.

**PR attribution:** `feat/corporate-actions-pr4-rebase` (PR4) introduced the migration behavior; the missing tests should be added there. PR5 added the totalSupply override and `LibTotalSupply` integration; the totalSupply-side tests should land in PR5.

### A03-P2-2 — `AccountMigrated` event emission has no test

**Severity:** LOW

(Subsumed by A03-P2-1 test G, but flagged separately so it isn't lost if A03-P2-1's larger fix is descoped.)
