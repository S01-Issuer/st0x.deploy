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

## Version-Based Multiplier System

Corporate actions use a lazy evaluation system with versioned multipliers:

### Global State
- **Version counter**: Increments with each corporate action execution
- **Version multipliers**: `mapping(version → multiplier)` for each corporate action
- **Current global version**: Latest version after all executed corporate actions

### Account State  
- **Account version**: `mapping(account → version)` tracking each account's current version
- **Base balance**: Account's balance as of their current version

### Lazy Evaluation
- **Read operations**: Apply all multipliers from account's version to global version sequentially
  - Example: `balance × multiplier_v4 × multiplier_v5 × multiplier_v6`
- **Write operations**: Update account to current global version with computed balance
- **Version updates**: Account version advances to global version after balance computation

### Precision Requirements
- **Rain float math**: Sequential multiplier application uses Rain's float library
- **Custodian matching**: Maintains exact correspondence with traditional stock split calculations
- **Clean ratios**: Supports precise fractional calculations (2:1, 3:2, 1:10) without degradation

## Initial Scope

**Focus on rebasing actions:**
- `STOCK_SPLIT_N_M` - split N shares into M shares (N < M)
- `REVERSE_SPLIT_N_M` - combine N shares into M shares (N > M) 
- Results in new version with corresponding multiplier

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

1. **Version precision** - Sequential multiplier application must mirror offchain stock split mechanics exactly to maintain 1:1 correspondence.

   **Traditional stock split mechanics:**
   - Common ratios: 2:1, 3:1, 3:2, 5:4, 1:10 (reverse) - always simple fractions
   - Calculation: `original_shares × (numerator/denominator) = entitled_shares`  
   - Example: 101 shares × (3/2) = 151.5 shares
   
   **Fractional share handling:**
   - Issue whole shares: `floor(entitled_shares)` = 151 shares
   - Cash in lieu: `(entitled_shares - whole_shares) × market_price` for 0.5 shares
   - Cost basis allocated proportionally for tax compliance
   
   **Version system requirements:**
   - Sequential multiplier application uses Rain float math for exact fractional calculations
   - Version-based balance computation reflects precise entitlements without approximation
   - Must match custodian's traditional split calculations exactly for regulatory compliance

2. **Batch operations** - Multiple related actions in single transaction handled via existing `multicall` function. VATS already implements `MulticallUpgradeable` - no additional implementation needed.

3. **Historical queries** - Events emitted for offchain indexing. Onchain indexing optimization deferred for now.

4. **Cross-chain synchronization** - Single chain focus initially. Cross-chain propagation addressed in future upgrade.