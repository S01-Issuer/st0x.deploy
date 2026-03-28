# Corporate Actions via Diamond Facet

## Overview

Corporate actions are implemented as a diamond facet on the existing OffchainAssetReceiptVault. This approach provides a single source of truth for external contracts while avoiding contract size limits and maintaining the vault's existing address.

## Architecture

The corporate action system uses a diamond facet pattern with shared storage and state management:

- **CorporateActionFacet**: New facet providing scheduling and execution functions
- **LibCorporateAction**: Shared storage library with state transition validation
- **Single address**: Vault retains same address for external contract compatibility

## Design Principles

1. **Don't scale user input**: User operations maintain constant gas costs regardless of corporate action history
2. **Sequential precision**: Apply multipliers sequentially to preserve computational behavior for custodian compliance
3. **Lazy migration**: Accounts migrate to current version only when interacting
4. **User intent preservation**: "1 share" always means 1 share at current value

## Corporate Action Types

### Rebase-Causing Actions
- **Stock splits**: Multiply token balances (e.g., 2:1 split doubles balances)
- **Reverse splits**: Divide token balances (e.g., 1:10 split reduces balances by 10x)
- **Stock dividends**: May cause balance multiplication depending on implementation

### Non-Rebase Actions
- **Name/symbol changes**: Update metadata without affecting balances
- **Cash dividends**: Separate distributions without balance modifications
- **Administrative actions**: Various corporate events without multiplier effects

## Technical Approach

### Version-Based Lazy Migration System

The system tracks corporate action effects through a version-based approach that minimizes gas costs:

#### Global State Management
- **Version counter**: Increments only when rebase-causing corporate actions execute
- **Version multipliers**: Sequential multipliers stored per version for precision correctness
- **Current global version**: Latest version reflecting all executed corporate actions

#### Account-Level Tracking  
- **Account versions**: Track current version per account for lazy evaluation
- **Base balances**: Account balances as of their current version

#### Migration Mechanics
- **Read operations**: Apply pending multipliers sequentially from account version to global version
- **Write operations**: Migration-then-write sequence ensures both sender and recipient are current before balance changes
- **Gas economics**: One-time migration cost per corporate action period, then normal ERC20 efficiency
- **Precision protection**: Multipliers applied to stored balances, never to user input amounts

### State Management

Corporate actions progress through enforced state transitions:
- **SCHEDULED**: Action planned for future execution
- **IN_PROGRESS**: Currently executing (transient state)
- **COMPLETE**: Successfully executed
- **EXPIRED**: Not executed within required window

### Execution Windows

Actions must execute within a fixed window after their effective time:
- **Window duration**: 4 hours after effective time
- **Purpose**: Provides timing certainty for external contracts and prevents indefinite delays
- **Enforcement**: Actions automatically expire if not executed within window

### Precision Requirements

The system maintains exact correspondence with traditional finance calculations:

#### Traditional Stock Split Mechanics
- **Ratios**: Always simple fractions (2:1, 3:2, 1:10) for clean mathematical operations
- **Calculation**: `original_shares × (split_ratio) = entitled_shares`
- **Fractional shares**: Handled via cash-in-lieu payments at market price
- **Cost basis**: Proportionally allocated for tax compliance

#### System Implementation
- **Sequential application**: Multipliers applied one-after-another to preserve computational precision
- **Rain float math**: Exact fractional calculations for regulatory compliance
- **Custodian matching**: Results must match traditional systems precisely

## Receipt Integration

The vault's manager relationship with receipt contracts enables coordinated corporate action handling:

### Manager-Directed Approach
- **Existing privileges**: Vault already manages receipt operations (used in withdrawals)
- **Coordinated execution**: Corporate actions trigger proportional adjustments in both vault and receipt balances
- **Single control point**: Vault's corporate action system drives both ERC20 and ERC1155 updates

### Implementation Benefits
- **Leverages existing architecture**: Uses established manager relationship
- **Consistent accounting**: Receipt and vault balances remain proportional
- **Simplified design**: Single version system drives both contracts
- **Regulatory compliance**: Receipt holders experience identical corporate action effects

## Oracle Compatibility

External contracts require specific capabilities for corporate action integration:

- **Query stored actions**: Access corporate action data directly from vault
- **Identify upcoming events**: Determine actions that may affect token behavior
- **Access historical data**: Retrieve past corporate actions for analysis
- **Check timing status**: Determine action scheduling and execution state

## Implementation Considerations

### OpenZeppelin v5 Integration
The system leverages OpenZeppelin v5's unified update hook:
- **Single hook**: `_update` handles all balance changes (transfers, mints, burns)
- **Migration pre-step**: Lazy migration occurs before any balance modifications
- **Bilateral migration**: Both sender and recipient updated to current version

### Batch Operations
Multiple corporate actions can be executed in single transactions using the vault's existing multicall functionality.

### Data Management
- **Event emission**: All corporate actions emit events for offchain indexing
- **Storage optimization**: Version-based approach minimizes storage requirements
- **Query efficiency**: External contracts query single vault address

### Cross-Chain Considerations
Initial implementation focuses on single-chain deployment. Cross-chain propagation of corporate actions will be addressed in future upgrades.

### Authorization
Corporate action operations integrate with the vault's existing authorization system:
- **Role-based permissions**: Different action types may require different authorization levels
- **Execution permissions**: Separate from scheduling permissions for operational flexibility
- **Governance integration**: Administrative actions follow established governance patterns