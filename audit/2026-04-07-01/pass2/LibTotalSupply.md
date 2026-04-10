# A28 — Pass 2 (Test Coverage): LibTotalSupply

**Source:** `src/lib/LibTotalSupply.sol`
**Tests:** `test/src/lib/LibTotalSupply.t.sol` (266 lines)

## Coverage observed (very thorough at the harness level)

- `testNoSplitsReturnsOzSupply` / `testVirtualFoldDoubles` / `testEagerFold`
- `testAccountMigration` / `testFullMigration`
- `testSecondSplitWithPartialMigration`
- `testFractionalPrecisionImprovement`
- `testMintAfterFold` / `testBurnAfterFold` / `testMintBeforeSplits`
- `testFoldIdempotent` / `testVirtualMatchesEager`
- `testSequentialPrecision`
- `testCrossEpochMigration`

## Findings

### A28-P2-1 — HIGH: No vault-level integration test composes LibTotalSupply with `_update`

**Severity:** HIGH (paired with A03-P2-1; same root coverage gap)

The harness (`LibTotalSupplyHarness`) exposes `onMint`, `onBurn`, `onAccountMigrated` as external callables that the test invokes directly. This is excellent for per-pot math verification but **never composes the library with a real `StoxReceiptVault._update`**, which is the only place where (a) the cursor for fresh accounts must be advanced, (b) `super._update` writes a stored balance after migration, (c) the real OZ totalSupply ticks and must agree with `effectiveTotalSupply`.

The integration tests proposed in `pass2/StoxReceiptVault.md::A03-P2-1` (specifically tests D, E, F) double as the missing coverage for `LibTotalSupply` composed with the vault. After those tests are in place, this finding closes.

### A28-P2-2 — `onBurn` underflow protection is not tested

**Severity:** LOW

**Location:** `src/lib/LibTotalSupply.sol:160` (`s.unmigrated[s.totalSupplyLatestSplit] -= amount;`)

If `amount > s.unmigrated[totalSupplyLatestSplit]`, Solidity 0.8 will revert with an underflow panic. There is no test that asserts this revert. Such a state shouldn't be reachable under normal vault operation (every burn is preceded by `_migrateAccount(burner)` which puts the burner's balance into the latest pot first), but the precondition is implicit. Adding a direct harness test that calls `onBurn` with an amount larger than the pot ensures the revert is the documented behavior and protects against a future refactor that adds an unchecked block.

**Suggested fix:** see `.fixes/A28-P2-2.md`.

### A28-P2-3 — No fuzz tests over `effectiveTotalSupply` with random pot configurations

**Severity:** INFO

The library's correctness depends on the per-pot bookkeeping invariant. A fuzz test that picks N random pots, M random multipliers, and asserts `effectiveTotalSupply()` matches a reference implementation would catch arithmetic regressions cheaply. INFO; not required for the current audit pass.
