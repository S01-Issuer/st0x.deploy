# A03 — Pass 3 (Documentation): StoxReceiptVault

**Source:** `src/concrete/StoxReceiptVault.sol`

## Findings

### A03-P3-1 — `AccountMigrated` event lacks `@param` documentation for individual fields

**Severity:** LOW

**Location:** `src/concrete/StoxReceiptVault.sol:24-27`

```solidity
/// Emitted when an account is migrated through pending stock splits.
event AccountMigrated(
    address indexed account, uint256 fromCursor, uint256 toCursor, uint256 oldBalance, uint256 newBalance
);
```

The event has a single-line `///` summary but no per-field `@param` tags. Five fields, each meaningful for offchain reconciliation, all undocumented. Indexers can't tell from the source whether `oldBalance` is the *stored* pre-migration balance or the *effective* (already-rebased) pre-migration balance.

**Suggested fix:** see `.fixes/A03-P3-1.md`.

### A03-P3-2 — Public `balanceOf` and `totalSupply` overrides lack `@return` documentation

**Severity:** INFO

**Location:** `src/concrete/StoxReceiptVault.sol:30, 38`

Both functions have `@dev` clauses describing what they include but no `@return` tag. Inherits the underlying ERC20 contract's NatSpec via `override`, so the omission is borderline. INFO; a one-line `@return` clarifying the rebase semantics would close it.

### A03-P3-3 — Migration is described as "lazy" in the contract NatSpec but the term "migrate" is overloaded

**Severity:** INFO

**Location:** `src/concrete/StoxReceiptVault.sol:11-22`

The contract NatSpec uses "migration" for two distinct things: (a) lazy rasterization of an account's stored balance to the post-rebase basis, and (b) advancing the account's cursor through the corporate action linked list. Most of the time these happen together; the A03-1 bug exists precisely because they can come apart. A clarifying note that distinguishes "balance migration" from "cursor migration" would aid future readers. INFO.
