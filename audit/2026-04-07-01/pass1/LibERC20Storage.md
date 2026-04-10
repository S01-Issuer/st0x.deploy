# A23 — Pass 1 (Security): LibERC20Storage

**File:** `src/lib/LibERC20Storage.sol` (59 lines)

## Evidence of thorough reading

**Library:** `LibERC20Storage`

**Functions:**
- `getBalance(address)` internal view — line 25
- `setBalance(address, uint256)` internal — line 36
- `getTotalSupply()` internal view — line 46
- `setTotalSupply(uint256)` internal — line 54

**Constants:**
- `ERC20_STORAGE_LOCATION` (file scope) — line 7

## Findings

### A23-1 — Tight coupling to OZ ERC20Upgradeable storage layout with no compile-time or test-time check that the layout still matches

**Severity:** MEDIUM

**Location:** `src/lib/LibERC20Storage.sol:5-20` (constant + safety comment), and entire library

The library hardcodes:
- The ERC-7201 namespaced slot for OZ's `ERC20Storage` struct (`0x52c63247...0bace00`).
- The struct field offsets: `_balances` at +0, `_totalSupply` at +2 (line 48: `add(ERC20_STORAGE_LOCATION, 2)`).

These match OZ v5's current `ERC20Upgradeable.sol`. The `SAFETY:` comment block (lines 15-20) acknowledges the brittleness in prose. **There is no mechanism that detects layout drift.** If OZ upstream renames a field, reorders, inserts a new field at offset +1, or moves to a different namespace string, this library will silently read/write the wrong slots. The vault's balance accounting will silently corrupt: `getBalance` will return zero / garbage / another field's contents, `setBalance` will overwrite an unrelated field.

The exposure is real because `lib/openzeppelin-contracts-upgradeable` is a git submodule and `foundry.toml` does not pin a specific OZ version through any compile-time enforcement of the slot constant — a `forge update` of the submodule could silently introduce drift.

**Impact:** Silent storage corruption of the receipt vault's ERC20 layer. The corruption would not be visible until balances are read (and would manifest as wrong balanceOf, wrong totalSupply, possibly wrong allowances) or until a setBalance corrupts the wrong slot. Severity is MEDIUM because exploitation requires an OZ upgrade — but the failure mode is silent and the blast radius is total.

**Suggested fix:** see `.fixes/A23-1.md`. Two complementary mitigations:
1. Add a runtime invariant test that constructs an OZ `ERC20Upgradeable` instance, mints to it, then asserts `LibERC20Storage.getBalance(alice) == ERC20Upgradeable.balanceOf(alice)` and `LibERC20Storage.getTotalSupply() == ERC20Upgradeable.totalSupply()`. This catches drift at CI time.
2. Document the exact OZ commit / version this layout was verified against, and add a comment requiring any submodule bump to re-verify the test.

### A23-2 — `setBalance` and `setTotalSupply` are unprotected library helpers

**Severity:** INFO

The functions are `internal` so they cannot be called from outside the deploying contract. Caller-side discipline is the only safeguard against accidentally desyncing `unmigrated[k]` accounting (LibTotalSupply pots) when balances are written. This is by design — the migration system depends on direct writes — but it's worth noting that any future caller of `LibERC20Storage.setBalance` who is not LibRebase / StoxReceiptVault must also call `LibTotalSupply.onAccountMigrated` (or equivalent pot bookkeeping) to keep totalSupply consistent. INFO; no action required today since only `_migrateAccount` calls `setBalance`.

## Items deliberately not flagged

- Assembly is `memory-safe` annotated, scratch space (`0x00`-`0x40`) is correctly used and not relied on after the keccak256.
- Slot derivation `keccak256(account || slot)` for `mapping(address => uint256)` matches Solidity's mapping storage encoding (verified mentally against the spec).
