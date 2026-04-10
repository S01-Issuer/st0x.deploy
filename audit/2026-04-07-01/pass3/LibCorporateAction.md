# A21 — Pass 3 (Documentation): LibCorporateAction

**Source:** `src/lib/LibCorporateAction.sol`

## Findings

### A21-P3-1 — `head()` and `tail()` accessors lack NatSpec

**Severity:** LOW

**Location:** `src/lib/LibCorporateAction.sol:216-222`

```solidity
function head() internal view returns (uint256) {
    return getStorage().head;
}

function tail() internal view returns (uint256) {
    return getStorage().tail;
}
```

Both are public-ish accessors used by tests and could be called by future facet methods. No `@notice`, `@dev`, or `@return`. Trivial fix; pure addition of three lines of NatSpec each.

**Suggested fix:** see `.fixes/A21-P3-1.md`.

### A21-P3-2 — Storage struct field documentation explains each field but not the relationship between `accountMigrationCursor`, `unmigrated`, `totalSupplyLatestSplit`, `totalSupplyBootstrapped`

**Severity:** INFO

**Location:** `src/lib/LibCorporateAction.sol:49-73`

Each field has a one-line comment explaining what it stores. The interaction between them — that `unmigrated[k]` is the sum of `getBalance(account)` over `account` such that `accountMigrationCursor[account] == k`, and that this invariant is what enables the per-pot precision improvement — is documented in `LibTotalSupply.sol`'s top-of-file comment, but a reader looking at `CorporateActionStorage` first would not know the cross-file relationship. A `@dev` block on the struct itself pointing to `LibTotalSupply` would help.

**Suggested fix:** see `.fixes/A21-P3-2.md`.
