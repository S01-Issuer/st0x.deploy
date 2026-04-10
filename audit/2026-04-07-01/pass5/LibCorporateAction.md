# A21 — Pass 5 (Correctness / Intent): LibCorporateAction

## Findings

### A21-P5-1 — `unmigrated` storage field name is misleading

**Severity:** INFO

**Location:** `src/lib/LibCorporateAction.sol:59-65`

```solidity
/// Per-cursor unmigrated supply. Maps cursor position (node index) to
/// the sum of stored balances for accounts at that cursor level.
mapping(uint256 => uint256) unmigrated;
```

The field is documented correctly in the comment, but the name "unmigrated" suggests "balance not yet migrated" — whereas the actual semantics is "sum of stored balances of accounts whose migration cursor is k." Migrated accounts that have just landed at cursor k contribute to `unmigrated[k]`, contradicting the name.

A better name would be `cursorPotBalance` or `balanceByCursor`. INFO; renaming a storage field across PRs is annoying and the comment is sufficient. No fix file.
