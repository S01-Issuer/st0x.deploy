# A01 — Pass 3 (Documentation): StoxCorporateActionsFacet

**Source:** `src/concrete/StoxCorporateActionsFacet.sol`

## Findings

### A01-P3-1 — Events `CorporateActionScheduled` and `CorporateActionCancelled` lack NatSpec

**Severity:** LOW

**Location:** `src/concrete/StoxCorporateActionsFacet.sol:14, 17`

```solidity
event CorporateActionScheduled(
    address indexed sender, uint256 indexed actionIndex, uint256 actionType, uint64 effectiveTime
);
event CorporateActionCancelled(address indexed sender, uint256 indexed actionIndex);
```

Both events are part of the public ABI used by offchain indexers and consumers (oracles, dashboards). They have no `@notice` describing what they signal, no `@param` describing each indexed/data field, and no `@dev` describing when they fire (before/after state mutation, before/after auth). Add NatSpec.

**Suggested fix:** see `.fixes/A01-P3-1.md`.

### A01-P3-2 — Contract `@notice` does not state that the facet must be delegatecalled by a vault

**Severity:** LOW

**Location:** `src/concrete/StoxCorporateActionsFacet.sol:11-13`

```solidity
/// @title StoxCorporateActionsFacet
/// @notice Diamond facet implementing the corporate action linked list.
```

The crucial usage constraint — "this contract must be delegatecalled by an `OffchainAssetReceiptVault` derivative; direct calls revert because `_authorize` reads the vault's authorizer state" — is implied only by the `_authorize` `@dev` comment at line 103. A future integrator reading just the contract `@notice` won't know that direct deployment + direct calls are unsupported. Add a `@dev` clause to the contract NatSpec.

**Suggested fix:** see `.fixes/A01-P3-2.md`.

### A01-P3-3 — `_authorize` lacks `@param` tags

**Severity:** INFO

`_authorize(address user, bytes32 permission)` has a `@dev` block but no `@param` documentation. Internal helper, lower priority than public surface. INFO.
