# Corporate Actions via Diamond Facet

## Overview

This specification defines a comprehensive corporate actions system implemented as a diamond facet, comprising multiple distinct components: a flexible framework for all corporate action types, specific implementation of supply-changing actions, and technical mechanisms for reliable downstream integration.

## System Components

### 1. Diamond Facet Architecture

**Purpose**: Introduce diamond facet pattern to vault for extensible functionality

**Key Features**:
- Maintains existing vault address for external contract compatibility
- Bypasses contract size limits for complex functionality
- Enables modular addition of corporate action types over time
- Provides shared storage and state management via LibCorporateAction

### 2. Corporate Actions Framework

**Purpose**: Flexible scheduling and execution system with timing enforcement

**Core Capabilities**:
- **Scheduling system**: Future-dated corporate action planning with metadata storage
- **State management**: Enforced transitions (SCHEDULED → IN_PROGRESS → COMPLETE/EXPIRED)
- **Execution windows**: 4-hour deadline enforcement for operational certainty
- **Authorization integration**: Role-based permissions via existing RBAC system
- **Event emission**: Comprehensive audit trail for offchain indexing

**Framework Benefits**:
- Extensible architecture for future corporate action types
- Predictable timing for downstream consumers
- Single source of truth for all corporate action data
- Operational discipline through execution deadlines

### 3. Supply-Changing Actions Implementation

**Purpose**: First corporate action types that modify token balances

**Initial Scope**:
- **Stock splits**: Multiply token balances (e.g., 2:1 split doubles balances)
- **Reverse splits**: Divide token balances (e.g., 1:10 split reduces by 90%)
- **Stock dividends**: Balance modifications for dividend reinvestment

**Design Requirements**:
- **Regulatory compliance**: Exact precision matching traditional finance calculations
- **Fractional handling**: Proper cash-in-lieu calculations for fractional shares
- **Custodian coordination**: Results identical to traditional systems for reconciliation

### 4. Sequential Rebase Technical Implementation

**Purpose**: Technical mechanism for implementing supply changes efficiently

**Core Technology**:
- **Version-based lazy migration**: Accounts migrate to current rebase state only when interacting
- **Sequential multiplier application**: Preserve computational precision for compliance
- **Storage rasterization**: Balance effects materialized during transfers via OpenZeppelin v5 `_update` hook
- **Rain float math integration**: Exact fractional calculations without precision loss

**Gas Economics**:
- **One-time migration cost**: Users pay rebase migration once per rebase period
- **Constant costs**: Gas independent of corporate action history
- **Efficient operations**: Normal ERC20 performance after migration
- **Non-rebase actions**: Zero migration overhead for non-balance-affecting actions

**Precision Requirements**:
- **Sequential vs cumulative**: Apply multipliers one-after-another to match traditional calculations
- **User intent preservation**: Input amounts never scaled by historical effects  
- **Computational correctness**: Preserve intended precision behavior including rounding

### 5. Downstream Consumer Integration

**Purpose**: Reliable interface for external contracts and oracles

**Query Capabilities**:
- **Corporate action data**: Direct vault queries for all scheduled and completed actions
- **Timing information**: Reliable execution windows and deadlines
- **Balance effect prediction**: Identify upcoming supply-changing events
- **Historical analysis**: Access to complete corporate action audit trail

**Integration Benefits**:
- **Oracle compatibility**: Standard interface for downstream protocol integration
- **Timing reliability**: External contracts can depend on execution window enforcement
- **Single address**: No need to track multiple contracts or registries
- **Comprehensive data**: Full context for risk management and automated responses

## Design Principles

### Framework-Level Principles (All Corporate Actions)
1. **Extensible architecture**: System supports addition of new corporate action types
2. **Enforced timing**: Execution windows provide operational certainty
3. **Single source of truth**: Vault address provides all corporate action information
4. **State consistency**: Enforced transitions prevent invalid states

### Rebase-Specific Principles (Supply-Changing Actions)
1. **Constant user costs**: Gas costs independent of corporate action history
2. **Sequential precision**: Preserve computational behavior for regulatory compliance
3. **Lazy evaluation**: Migration occurs only when accounts interact
4. **User intent preservation**: Input amounts represent current value, not historical units

## Receipt System Integration

**Manager-Directed Coordination**: Leverages existing vault-receipt manager relationship

**Approach**:
- Corporate action execution triggers proportional ERC1155 receipt adjustments
- Same multipliers applied to both vault shares and receipts for consistency
- Single system drives both ERC20 and ERC1155 updates via manager privileges
- Unified query interface through vault for all corporate action effects

**Benefits**:
- Consistent accounting between vault shares and receipts
- Leverages established architecture without parallel systems
- Regulatory compliance for all token holders regardless of token type

## Technical Considerations

### OpenZeppelin v5 Integration
- Single `_update` hook handles all balance modifications
- Migration logic implemented as pre-step before balance changes
- Both sender and recipient migrated to current state during transfers

### Precision and Compliance
- Traditional stock split ratios: simple fractions (2:1, 3:2, 1:10) for clean calculations
- Fractional share handling: floor entitlements with cash-in-lieu for remainder
- Cost basis allocation: proportional division for tax compliance
- Rain float math: sequential application maintains exact correspondence

### Storage and Performance
- Diamond storage pattern for shared state management
- Event emission for comprehensive offchain indexing
- Batch operations via existing multicall functionality
- Optimized gas costs through lazy evaluation design

### Authorization and Security
- Role-based permissions for different corporate action types
- Execution permissions separate from scheduling for operational flexibility
- Integration with existing governance patterns for administrative actions