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

**Problem**: Need standardized system for scheduling, tracking, and executing various corporate action types with reliable timing for downstream consumers.

**Solution**: Comprehensive framework providing:
- **Scheduling system**: Future-dated corporate action planning with metadata storage
- **State management**: Enforced transitions (SCHEDULED → IN_PROGRESS → COMPLETE/EXPIRED)
- **Execution windows**: 4-hour deadline enforcement for operational certainty
- **Authorization integration**: Role-based permissions via existing RBAC system
- **Event emission**: Comprehensive audit trail for offchain indexing
- **Single source of truth**: All corporate action data queryable from vault address

**Benefits**:
- Extensible architecture for future corporate action types
- Predictable timing for downstream consumers
- Operational discipline through execution deadlines

### 3. Supply-Changing Actions Implementation

**Purpose**: First corporate action types that modify token balances

**Initial Scope**:
- **Stock splits**: Multiply token balances (e.g., 2:1 split doubles balances)
- **Reverse splits**: Divide token balances (e.g., 1:10 split reduces by 90%)
- **Stock dividends**: Balance modifications for dividend reinvestment

### 4. Sequential Rebase Technical Implementation

**Purpose**: Handle the complex problem of applying balance changes to thousands of token holders without unbounded gas costs while maintaining precision

**Problem**: When corporate actions require balance changes across all token holders, traditional approaches fail:
- **Eager updates**: Updating all accounts during corporate action execution requires unbounded gas
- **Simple multipliers**: Cumulative multipliers introduce precision errors over time 
- **Direct scaling**: Applying multipliers to user inputs contaminates user intent

**Solution**: Version-based lazy migration system that solves these constraints:

**Version System**: Each account tracks a version number representing their current state relative to executed corporate actions. When corporate actions execute, a global version increments and stores the associated multiplier, but individual accounts remain at their current version until they interact.

**Lazy Migration**: When accounts interact (transfers, mints, burns), both sender and recipient are "migrated" to the current global version by applying any pending multipliers to their stored balances, then advancing their version number. This ensures both parties operate on current effective balances before any balance changes.

**Sequential Precision**: Multipliers are applied one-after-another in the same order they were executed, preserving the exact computational sequence. This avoids precision differences between sequential and cumulative application that arise from floating-point arithmetic.

Consider David's example: a series of corporate actions with multipliers 1/3, then 3x, then 1/3, then 3x:
- **Sequential application**: `100 × (1/3) × 3 × (1/3) × 3 = 99.999999...` (due to accumulated rounding errors)
- **Cumulative application**: `100 × 1 = 100.000000` (exact, since mathematically 1/3 × 3 × 1/3 × 3 = 1)

Even though mathematically equivalent, the computational results differ. Sequential application preserves the intended computational behavior including its precision characteristics, while cumulative optimization would "fix" precision errors and produce different results.

**User Intent Preservation**: The migration happens to stored balances during write operations, never to user input amounts. When a user transfers "1 share," they get exactly 1 share at current value regardless of corporate action history.

**Implementation Details**:
- OpenZeppelin v5 `_update` hook provides single integration point for all balance changes
- Rain float math library ensures exact fractional calculations
- Both sender and recipient migrated before balance modifications
- One-time migration cost per corporate action period, then normal ERC20 efficiency

### 5. Downstream Consumer Interface

**Purpose**: Reliable interface for external contracts and oracles

**Query Capabilities**:
- **Corporate action data**: Direct vault queries for all scheduled and completed actions
- **Timing information**: Reliable execution windows and deadlines
- **Balance effect prediction**: Identify upcoming supply-changing events
- **Historical analysis**: Access to complete corporate action audit trail

**Benefits**:
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
2. **Sequential precision**: Preserve computational behavior including rounding characteristics
3. **Lazy evaluation**: Migration occurs only when accounts interact
4. **User intent preservation**: Input amounts represent current value, not historical units

## Receipt System Integration

**Manager-Directed Coordination**: Leverages existing vault-receipt manager relationship

**Problem**: Corporate actions must affect both ERC20 vault shares and ERC1155 receipts consistently to maintain proportional accounting.

**Solution**: When vault executes corporate actions, it uses existing manager privileges to trigger proportional adjustments in receipt balances. Same multipliers applied to both systems ensure consistency.

**Benefits**:
- Consistent accounting between vault shares and receipts
- Leverages established architecture without parallel systems
- Single control point drives both ERC20 and ERC1155 updates

## OpenZeppelin v5 Integration

The lazy migration system integrates with OpenZeppelin v5's unified balance update architecture:

**Single Hook Integration**: The `_update` hook handles all balance changes (transfers, mints, burns), providing a single point to implement migration logic as a pre-step before any balance modifications.

**Migration Pre-Step**: Before balance changes occur, both sender and recipient accounts are migrated to current version if needed, ensuring all operations work with current effective balances.

## Precision and Computational Correctness

**Sequential vs Cumulative Multipliers**: Corporate actions must be applied in the same computational sequence to preserve precision characteristics. Sequential application may accumulate small rounding errors that cumulative application would avoid, but this preserves the intended computational behavior.

**Rain Float Math Integration**: All multiplier calculations use Rain's float library to handle fractional calculations precisely, supporting clean ratios (2:1, 3:2, 1:10) without degradation.

## Storage and Performance

**Diamond Storage Pattern**: Shared state management across facets with collision-resistant storage slots.

**Event Emission**: All corporate actions emit comprehensive events for offchain indexing and external system integration.

**Batch Operations**: Multiple corporate actions can be executed in single transactions using existing multicall functionality.