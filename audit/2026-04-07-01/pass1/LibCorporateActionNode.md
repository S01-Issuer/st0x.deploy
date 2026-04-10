# A22 — Pass 1 (Security): LibCorporateActionNode

**File:** `src/lib/LibCorporateActionNode.sol` (110 lines)

## Evidence of thorough reading

**Library:** `LibCorporateActionNode`

**Struct:** `CorporateActionNode` (file scope) — line 15
- `uint256 actionType` — line 17
- `uint64 effectiveTime` — line 19
- `uint256 prev` — line 21
- `uint256 next` — line 23
- `bytes parameters` — line 25

**Enum:** `CompletionFilter { ALL, COMPLETED, PENDING }` — line 35

**Functions:**
- `nextOfType(uint256, uint256, CompletionFilter)` internal view — line 55
- `prevOfType(uint256, uint256, CompletionFilter)` internal view — line 87

## Findings

None. Traversal logic is bounded by linked-list length, completed/pending early-break optimizations are correct given the time-ordered list invariant, and out-of-bounds `fromIndex` cleanly panics on `s.nodes[fromIndex].next/prev` access (Solidity default).
