# Corporate Actions Implementation Plan

## Overview

This plan implements corporate actions via diamond facet with sophisticated lazy migration for rebase-causing events while handling the complete spectrum of corporate action types.

## Architecture Summary

### Core System
- **Diamond facet**: Adds functionality without size limits or address changes
- **Version-based lazy migration**: Gas-efficient handling of rebase-causing corporate actions
- **Sequential precision**: Computational correctness for regulatory compliance
- **Manager-directed receipts**: ERC1155 coordination via existing vault privileges

### Design Principles
- **Constant user costs**: Gas costs independent of corporate action history
- **Lazy evaluation**: Migration only on account interaction
- **Precision preservation**: Sequential multipliers for custodian compliance
- **User intent protection**: Input amounts never scaled by historical multipliers

## Implementation Roadmap

### PR 1: Diamond Facet Infrastructure
**Goal**: Establish diamond facet and core storage architecture

**Key Components**:
- Corporate action storage with diamond storage pattern
- Version counter and multiplier mapping infrastructure  
- Account version tracking for lazy migration
- State transition validation framework
- Basic facet contract with function selectors

**Critical Validations**:
- Diamond storage pattern integration works correctly
- State transitions enforce valid progressions only
- Version tracking mechanisms function properly
- Facet function routing operates as expected

### PR 2: Corporate Action Scheduling
**Goal**: Implement corporate action lifecycle with execution windows

**Key Components**:
- Scheduling functions for different corporate action types
- Execution window enforcement (4-hour deadline)
- State management (SCHEDULED → IN_PROGRESS → COMPLETE/EXPIRED)
- Authorization integration with existing RBAC system
- Event emission for offchain indexing

**Critical Validations**:
- Corporate actions can be scheduled with appropriate authorization
- Execution windows properly enforced with automatic expiration
- State transitions work correctly through complete lifecycle
- Events provide sufficient data for external indexing
- Authorization checks prevent unauthorized scheduling

### PR 3: Lazy Migration System
**Goal**: Implement version-based lazy migration for rebase-causing actions

**Key Components**:
- OpenZeppelin v5 `_update` hook integration
- Account migration logic triggered by balance operations
- Sequential multiplier application using Rain float math
- Version advancement for both sender and recipient
- Rebase vs non-rebase corporate action handling

**Critical Validations**:
- Migration triggers correctly for both parties in transfers
- Sequential multiplier application maintains precision
- One-time migration cost per corporate action period
- User input amounts preserved without scaling
- Non-rebase actions avoid unnecessary migration costs
- Rain float math integration provides exact calculations

### PR 4: Receipt Integration & System Completion
**Goal**: Coordinate ERC1155 receipts and complete system validation

**Key Components**:
- Manager-directed receipt balance adjustments
- Coordinated execution affecting both vault and receipt balances
- Oracle compatibility for external contract queries
- Comprehensive edge case handling
- Performance optimization and gas cost validation

**Critical Validations**:
- Receipt and vault balances remain proportional after corporate actions
- Manager-directed updates work correctly via existing privileges  
- External contracts can query corporate action data effectively
- Edge cases handled properly (multiple simultaneous actions, complex migration scenarios)
- System maintains predictable gas costs across all operations
- No regressions in existing vault or receipt functionality

## Testing Strategy

### Unit Testing
- Individual component validation for storage, state transitions, and migration logic
- Authorization and permission enforcement verification
- Precision validation for sequential multiplier application

### Integration Testing  
- End-to-end corporate action lifecycle from scheduling through execution
- Migration system interaction with normal vault operations
- Receipt coordination via manager relationship

### Performance Testing
- Gas cost validation for migration operations
- Scalability testing with varying corporate action histories
- Comparison of rebase vs non-rebase action costs

### Regulatory Compliance Testing
- Precision validation against traditional stock split calculations
- Fractional share handling verification
- Custodian reconciliation simulation

## Success Criteria

### Functional Requirements
- Corporate actions execute correctly with appropriate balance effects
- Lazy migration provides constant gas costs regardless of history
- Sequential precision matches traditional finance calculations
- Receipt integration maintains proportional accounting

### Performance Requirements  
- Migration cost amortized across corporate action periods
- Normal operations maintain ERC20-level efficiency after migration
- System scales with active users, not total token holders

### Integration Requirements
- External contracts can query corporate action data effectively
- Oracle compatibility enables downstream protocol integration
- Authorization system properly controls corporate action operations

### Compliance Requirements
- Precision matches custodian calculations exactly
- Regulatory requirements for fractional share handling met
- Audit trail preserved for all corporate action events