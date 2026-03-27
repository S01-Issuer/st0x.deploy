# Corporate Actions via Diamond Facet

## Overview

Corporate actions (stock splits, reverse splits, etc.) are implemented as a diamond facet on the existing OffchainAssetReceiptVault. This provides a single source of truth for external contracts like oracles while avoiding contract size limits.

## Architecture

### Diamond Facet Pattern
- `CorporateActionFacet` - new facet with scheduling and execution functions
- `LibCorporateAction` - shared storage and state transition logic  
- Vault retains same address - external contracts query it directly

### Core Entities

**Corporate Action:**
```solidity
struct CorporateAction {
    bytes32 actionType;      // STOCK_SPLIT_2_1, REVERSE_SPLIT_1_10, etc.
    bytes data;              // Action-specific parameters
    uint256 effectiveTime;   // When this action takes effect
    uint256 scheduledAt;     // When this action was scheduled
    ActionState state;       // Current lifecycle state
}

enum ActionState {
    SCHEDULED,    // Action scheduled, pending execution
    IN_PROGRESS,  // Currently executing (transient)
    COMPLETE,     // Execution finished
    EXPIRED       // Not executed within window
}
```

### State Transitions
Enforced in `LibCorporateAction`:
```solidity
// Only valid transitions
SCHEDULED → IN_PROGRESS → COMPLETE
SCHEDULED → EXPIRED (if execution window passed)

// State change functions with validation
function startExecution(uint256 actionId) internal;
function completeAction(uint256 actionId) internal; 
function expireAction(uint256 actionId) internal;
```

### Execution Windows
- `EXECUTION_WINDOW = 4 hours` after `effectiveTime`
- Actions must execute within window or become EXPIRED
- Provides timing certainty for external contracts

## Initial Scope

**Focus on rebasing actions:**
- `STOCK_SPLIT_N_M` - split N shares into M shares (N < M)
- `REVERSE_SPLIT_N_M` - combine N shares into M shares (N > M) 
- Results in multiplier changes on the vault

**Not in scope yet:**
- Name/symbol changes
- Dividend distributions
- Other non-rebasing actions

## Oracle Compatibility

External contracts need to be able to:

- Query corporate actions stored directly on the vault
- Identify upcoming actions that may affect token behavior (e.g., rebases)  
- Access historical corporate action data for analysis
- Determine action timing and execution status

## Authorization

- Corporate action scheduling requires appropriate roles via existing Authorizer
- Same RBAC pattern as other vault operations
- Role-based permissions for different action types

## Key Benefits

1. **Single source of truth** - oracles query vault directly
2. **No size limits** - diamond facet pattern
3. **Enforced state transitions** - LibCorporateAction validates changes
4. **Composable** - external systems filter for actions they care about
5. **Consistent address** - vault address unchanged for external contracts

## Implementation Notes

1. **Multiplier precision** - Split ratios must mirror offchain precision exactly to maintain 1:1 correspondence. Traditional stock splits use simple ratios (2:1, 3:1, 1:10, etc.) that should translate cleanly to fixed-point arithmetic without rounding errors.

2. **Batch operations** - Multiple related actions in single transaction can be handled via multicall pattern. VATS may already implement this functionality.

## Future Considerations

3. **Historical queries** - Indexing strategy for large corporate action histories
4. **Cross-chain synchronization** - How corporate actions propagate across chains where vault is deployed