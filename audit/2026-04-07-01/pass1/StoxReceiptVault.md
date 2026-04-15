# A03 — Pass 1 (Security): StoxReceiptVault

**File:** `src/concrete/StoxReceiptVault.sol` (79 lines)

## Evidence of thorough reading

**Contract:** `StoxReceiptVault is OffchainAssetReceiptVault`

**Functions:**
- `balanceOf(address)` public view virtual override — line 30
- `totalSupply()` public view virtual override — line 38
- `_update(address, address, uint256)` internal virtual override — line 44
- `_migrateAccount(address)` private — line 59

**Events:**
- `AccountMigrated(address indexed account, uint256 fromCursor, uint256 toCursor, uint256 oldBalance, uint256 newBalance)` — line 25

**Types/errors/constants:** none defined here.

## Findings

### A03-1 — CRITICAL: mint or transfer to a fresh recipient after a completed split over-multiplies the recipient's balance, minting tokens out of thin air

**Severity:** CRITICAL

**Locations:**
- `src/concrete/StoxReceiptVault.sol:59-78` (`_migrateAccount`)
- `src/lib/LibRebase.sol:38-40` (`migratedBalance` early return for zero balance)
- The flawed behavior is enshrined as "correct" in `test/src/lib/LibRebase.t.sol:42-48` (`testZeroBalanceUnchanged`)

**Reproduction (mint pathway):**

1. A 2x stock split is scheduled and its `effectiveTime` passes.
2. A fresh account `alice` (never touched the vault, `LibERC20Storage.getBalance(alice) == 0`, `accountMigrationCursor[alice] == 0`) receives a mint of 100 tokens.
3. `_update(0, alice, 100)` runs:
   - `LibTotalSupply.fold()` bootstraps and sets `totalSupplyLatestSplit = 1`.
   - `_migrateAccount(0)` early-returns (zero address).
   - `_migrateAccount(alice)`: `storedBalance = 0`, `currentCursor = 0`. `LibRebase.migratedBalance(0, 0)` walks zero iterations because of the line 38 early return and returns `(0, 0)`. The `if (newCursor == currentCursor) return;` guard at line 68 fires, so **the cursor is never advanced**. Alice's `accountMigrationCursor` remains 0.
   - `LibTotalSupply.onMint(100)` adds 100 to `unmigrated[1]`.
   - `super._update(0, alice, 100)` writes `_balances[alice] = 100` via OZ.
4. Now query `balanceOf(alice)`:
   - `stored = LibERC20Storage.getBalance(alice) = 100`
   - `accountMigrationCursor[alice] = 0`
   - `LibRebase.migratedBalance(100, 0)` walks completed splits from cursor 0, finds the 2x split, returns `(200, 1)`.
   - **Returns 200.**
5. Alice was minted 100 tokens but her balance reads as 200. The extra 100 are not backed by anything. `totalSupply()` and the sum of per-account `balanceOf` now disagree (totalSupply correctly reflects the mint at the post-rebase basis, balanceOf doubles it).

**Reproduction (transfer pathway):** Identical bug, slightly different setup:
1. 2x split completes.
2. Existing holder `alice` (stored=50, cursor=0) calls `transfer(bob, 100)` where `bob` is a fresh account.
3. `_update(alice, bob, 100)`:
   - `_migrateAccount(alice)` migrates her to cursor 1, balance 100. Pots: `unmigrated[0] -= 50`, `unmigrated[1] += 100`.
   - `_migrateAccount(bob)` early-returns (zero balance). Bob stays at cursor 0.
   - `super._update(alice, bob, 100)` sets `_balances[alice] = 0`, `_balances[bob] = 100`.
4. `balanceOf(bob)` = `migratedBalance(100, 0)` = `(200, 1)` = **200**. Bob received 100 but reads 200.
5. `totalSupply()` walks pots and returns `trunc(unmigrated[0] * 2) + unmigrated[1]` (with corrected totals, this is the total of the rebased existing supply plus the originally-minted amount). Sum of `balanceOf` over all accounts is one 2x multiple higher than totalSupply.

**Root cause:** `LibRebase.migratedBalance` treats zero balance as "nothing to do" and returns the cursor unchanged. `_migrateAccount` then short-circuits and doesn't update storage. The cursor must be advanced regardless of balance — otherwise, after a subsequent stored-balance write (via `super._update` for mint or transfer-in), the next read interprets that already-rebased balance as if it were pre-rebase and re-applies the multiplier.

**Why the test suite misses this:**
- `test/src/lib/LibRebase.t.sol::testZeroBalanceUnchanged` (line 42) explicitly asserts `cursor == 0` after migration of a zero balance with a completed split — codifying the wrong behavior.
- `test/src/concrete/StoxReceiptVault.t.sol` has exactly one test (`testConstructorDisablesInitializers`) and contains zero coverage for `balanceOf`, `totalSupply`, `_update`, `_migrateAccount`, or any of their interactions with the corporate actions linked list.
- Library-level tests (`LibRebase.t.sol`, `LibTotalSupply.t.sol`) hit the libraries directly via harness contracts but never composed with a real ERC20 mint or transfer through the vault. The bug only manifests at the vault level after `super._update` writes a non-zero balance to a cursor=0 account.

**Impact:** **Critical solvency / inflation bug.** Any mint or transfer to a previously inactive account, after at least one stock split has completed, immediately credits the recipient with `(split_multiplier_product - 1) × intended_amount` extra tokens. For a forward 2x split this doubles the credited amount; for two consecutive 2x splits it quadruples it. The recipient can withdraw or transfer these phantom tokens immediately because per-account `balanceOf` reflects them. The wrapped vault's ERC4626 share-price math, oracle integrations using `balanceOf`, and any onchain consumer of these tokens are all corrupted. Inflation is unbounded over time as splits accumulate and any new account can be used as a faucet by routing tokens through it.

**PR attribution:** PR4 (`feat/corporate-actions-pr4-rebase`, commit `235ee7c` "feat: add StoxReceiptVault balance migration and LibERC20Storage"). The early-return shortcut in `LibRebase.migratedBalance` was introduced in the same PR.

**Proposed fix:** see `.fixes/A03-1.md`.

### A03-2 — `_migrateAccount` writes the new cursor without bounds-check that the linked list invariants still hold

**Severity:** INFO

**Location:** `src/concrete/StoxReceiptVault.sol:70`

`s.accountMigrationCursor[account] = newCursor;` is set to whatever `LibRebase.migratedBalance` returned. Library-level enforcement is correct (newCursor is always a valid completed-split node index when modified), so this is INFO-only — but if a future refactor invalidates the invariant, the lack of a defensive check at the vault layer means corrupted cursors propagate silently. Note for future maintainers; no action required today.

## Items deliberately not flagged

- The use of `LibERC20Storage.getBalance` / `setBalance` to bypass `_update` is intentional and necessary so migration writes don't emit spurious Transfer events. It is safe **as a mechanism**; the bug is in the cursor advancement logic, not the direct-write design.
- Reentrancy: `_update` is internal and the vault's external mint/burn/transfer entry points are protected by OZ's standard checks. No external calls happen between `_migrateAccount` and `super._update`.
