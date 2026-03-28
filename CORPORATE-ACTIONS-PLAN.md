# Corporate Actions Implementation Plan

## Overview

This plan implements a comprehensive corporate actions system comprising five distinct components: diamond facet architecture, flexible framework with timing enforcement, supply-changing actions, sequential rebase implementation, and downstream integration.

## System Architecture

### Component Integration
- **Diamond facet foundation**: Extensible architecture for corporate action functionality
- **Framework layer**: General scheduling, timing, and state management for all action types  
- **Supply-change implementation**: Specific handling of balance-affecting corporate actions
- **Technical rebase system**: Lazy migration and precision preservation for regulatory compliance
- **Consumer integration**: Reliable interface for external contracts and oracles

### Design Approach
- **Extensible framework**: Built to support future corporate action types beyond initial scope
- **Operational reliability**: Timing enforcement and execution windows for downstream certainty
- **Regulatory compliance**: Exact precision matching traditional finance for supply-changing actions
- **Gas optimization**: Lazy evaluation minimizes costs for users

## Implementation Roadmap

### PR 1: Diamond Facet Foundation
**Goal**: Establish diamond facet architecture and core infrastructure

**System Components Addressed**:
- Diamond facet pattern introduction
- Basic corporate action storage framework
- Foundation for extensible architecture

**Key Deliverables**:
- Diamond storage pattern integration with existing vault
- Core corporate action data structures and storage
- Basic facet contract with function selector routing  
- State transition validation framework
- Foundation storage for timing and authorization systems

**Critical Validations**:
- Diamond pattern integrates correctly with existing vault architecture
- Storage patterns support extensible corporate action types
- Facet routing works properly for corporate action functions
- Foundation supports both framework and rebase-specific requirements

### PR 2: Framework with Timing Enforcement  
**Goal**: Implement flexible corporate action framework with operational timing

**System Components Addressed**:
- Corporate actions framework (scheduling and execution)
- Timing enforcement and execution windows
- General state management for all corporate action types

**Key Deliverables**:
- Corporate action scheduling system for all action types
- Execution window enforcement (4-hour deadline after effective time)
- State management with enforced transitions (SCHEDULED → IN_PROGRESS → COMPLETE/EXPIRED)
- Authorization integration with existing RBAC system
- Event emission for comprehensive audit trails
- Query interfaces for external contracts

**Critical Validations**:
- All corporate action types can be scheduled with appropriate metadata
- Execution windows enforced consistently with automatic expiration
- State transitions prevent invalid progressions
- Authorization properly controls scheduling and execution
- Events provide sufficient data for downstream consumers
- External contracts can reliably query corporate action data and timing

### PR 3: Supply-Changing Actions & Rebase Implementation
**Goal**: Implement stock splits/reverse splits with sequential rebase system

**System Components Addressed**:
- Supply-changing actions implementation (specific corporate action types)
- Sequential rebase technical implementation
- Precision preservation and regulatory compliance

**Key Deliverables**:
- Stock split and reverse split corporate action types
- Version-based lazy migration system using OpenZeppelin v5 `_update` hook
- Sequential multiplier application with Rain float math integration
- Account migration logic for both sender and recipient during transfers
- Balance rasterization to storage during write operations
- Precision preservation for custodian compliance

**Critical Validations**:
- Stock splits and reverse splits execute with correct balance effects
- Migration triggers appropriately for both parties in transfers
- Sequential multiplier application maintains exact precision
- One-time migration cost per rebase period with normal ERC20 efficiency afterward
- User input amounts preserved without historical scaling
- Rain float math produces results matching traditional finance calculations
- Non-rebase actions avoid unnecessary migration overhead

### PR 4: Receipt Integration & System Completion
**Goal**: Complete system with ERC1155 receipt coordination and validation

**System Components Addressed**:
- Receipt system integration via manager relationship
- Downstream consumer integration completion
- System-wide validation and optimization

**Key Deliverables**:
- Manager-directed receipt balance adjustments coordinated with corporate actions
- Receipt system responds correctly to vault corporate action execution
- Complete external contract integration for reliable queries
- Comprehensive edge case handling (multiple simultaneous actions, complex migration scenarios)
- Performance optimization and gas cost validation across all system components
- Complete documentation for external integrators

**Critical Validations**:
- Receipt and vault balances remain proportional after all corporate action types
- Manager relationship works correctly for coordinated updates
- External contracts can depend on timing enforcement for operational decisions
- Edge cases handled properly across framework and rebase systems
- Gas costs remain predictable across complete system
- No regressions in existing vault, receipt, or authorization functionality
- System provides reliable interface for downstream consumers

## Testing Strategy

### Component-Level Testing
- **Diamond facet**: Integration with existing vault, storage patterns, function routing
- **Framework**: Scheduling, timing enforcement, state transitions, authorization
- **Supply actions**: Stock splits, reverse splits, precision calculations
- **Rebase system**: Migration triggers, sequential multipliers, gas optimization
- **Integration**: Receipt coordination, external contract compatibility

### System-Level Testing  
- **Complete corporate action lifecycle**: Schedule through execution across all components
- **Mixed action scenarios**: Rebase and non-rebase actions in sequence
- **Performance validation**: Gas costs across different corporate action histories
- **Regulatory compliance**: Precision matching with traditional finance calculations

### External Integration Testing
- **Oracle simulation**: External contracts querying corporate action data
- **Timing reliability**: Downstream systems depending on execution windows
- **Authorization integration**: Role-based access across all system components

## Success Criteria

### Framework Success
- **Extensible architecture**: System supports addition of new corporate action types
- **Timing reliability**: Execution windows provide operational certainty for external contracts
- **Authorization integration**: Role-based permissions work across all corporate action types
- **Audit compliance**: Complete event trail for all corporate action activities

### Supply-Change Success  
- **Regulatory compliance**: Exact precision matching traditional finance calculations
- **Gas optimization**: Constant user costs independent of corporate action history
- **User experience**: Input amounts represent current value without historical scaling
- **Custodian reconciliation**: Results match traditional systems exactly

### Integration Success
- **Single source of truth**: External contracts query vault directly for all corporate action data
- **Receipt consistency**: ERC1155 and ERC20 balances remain proportional
- **Performance**: System scales with active users, not total corporate action history
- **Reliability**: Downstream consumers can depend on timing and data accuracy