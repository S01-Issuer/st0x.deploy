# A01 — Pass 4 (Code Quality): StoxCorporateActionsFacet

## Findings

### A01-P4-1 — Four near-identical external traversal wrappers

**Severity:** INFO

**Location:** `src/concrete/StoxCorporateActionsFacet.sol:44-101`

`latestActionOfType`, `earliestActionOfType`, `nextOfType`, `prevOfType` all share the same 8-line shape: call a `LibCorporateActionNode` traversal function, then if the resulting cursor is non-zero, decode the node's `actionType` and `effectiveTime` and return them as a triple.

A small private helper (`_unpackNode(uint256 cursor)` returning the triple) would dedupe ~24 lines. Worth it only if a future facet method adds more traversal entry points; for the current four, the duplication is bearable. INFO; no fix file.
