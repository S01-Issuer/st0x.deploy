# A28 — Pass 1 (Security): LibTotalSupply

**File:** `src/lib/LibTotalSupply.sol` (163 lines)

## Evidence of thorough reading

**Library:** `LibTotalSupply`

**Functions:**
- `effectiveTotalSupply()` internal view returns (uint256) — line 69
- `fold()` internal — line 108
- `onAccountMigrated(uint256, uint256, uint256, uint256)` internal — line 138
- `onMint(uint256)` internal — line 148
- `onBurn(uint256)` internal — line 157

## Findings

### A28-1 — Pots become inconsistent with per-account `balanceOf` whenever A03-1 fires

**Severity:** HIGH (consequence of CRITICAL A03-1, distinct user-visible symptom)

**Location:** entire library; trigger lives in `StoxReceiptVault._migrateAccount` and `LibRebase.migratedBalance`

The pot accounting is correct given the precondition that every account's stored balance lives at the cursor recorded in `accountMigrationCursor[account]`. A03-1 violates that precondition for fresh recipients of mints/transfers — their stored balance is post-rebase but their cursor is 0. Once the bug fires:

- `unmigrated[0]` does not contain the fresh account's balance (because no `onAccountMigrated(0, …)` was called).
- `unmigrated[totalSupplyLatestSplit]` contains the mint amount (added via `onMint` at line 151) for mint paths, but contains nothing for transfer paths (transfers do not call `onMint`).
- `effectiveTotalSupply` returns a value consistent with what was added to the pots, but per-account `balanceOf(fresh_account)` returns the over-multiplied value.
- **Sum of `balanceOf(account)` over all accounts ≠ `totalSupply()`.** This breaks any external integrator that uses ERC20 invariants (ERC4626 vaults, lending protocols, oracles).

For the transfer-to-fresh-recipient path, the discrepancy is exactly `(split_multiplier_product − 1) × transferred_amount`. For mint-to-fresh, same formula. The discrepancy compounds over time as more splits occur.

**Why this is a HIGH separate finding rather than just a consequence of A03-1:** the test suite for LibTotalSupply (`test/src/lib/LibTotalSupply.t.sol`) is comprehensive at the harness level (266 lines, multiple scenarios) but **never composes the library with a real ERC20 mint to a fresh account**. Every test that calls `onMint` either calls it on a freshly bootstrapped harness with no per-account balances at all (`testMintAfterFold`, line 188), or operates entirely on the harness without going through StoxReceiptVault. The integration gap is the same as A03-1's: no test crosses the library boundary into the vault's `_update` pathway. Fixing A03-1 fixes this finding too — but the missing integration test must be added so this can never silently regress.

**Suggested fix:** A28-1 has no separate code fix beyond A03-1's. The remediation is the test added per A28-1's Pass 2 partner finding (`pass2/StoxReceiptVault.md::A03-P2-1`).

## Items deliberately not flagged

- `fold()` bootstrap-from-OZ math is correct: `unmigrated[0]` captures pre-bootstrap totalSupply, future mints add to `unmigrated[totalSupplyLatestSplit]`, walking pots reproduces the rebased total.
- Sequential rasterization in the pot walk (line 95-97) matches `LibRebase` for consistency between per-account and aggregate computations after migration.
- `onMint`/`onBurn` correctly no-op when `!totalSupplyBootstrapped` because in that branch OZ's `_totalSupply` is the source of truth and `effectiveTotalSupply` returns `LibERC20Storage.getTotalSupply()` (line 84).
- `int256(running)` unsafe cast at line 96 is the same INFO as A26-2 — same suppression, same realism caveat.
