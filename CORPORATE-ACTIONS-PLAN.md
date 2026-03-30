# Corporate Actions Implementation Plan

## Overview

This plan implements a comprehensive corporate actions system comprising five distinct components: diamond facet architecture, flexible framework with timing enforcement, supply-changing actions, sequential rebase implementation, and downstream consumer interface.

## System Architecture

### Component Integration
- **Diamond facet foundation**: Extensible architecture for corporate action functionality
- **Framework layer**: General scheduling, timing, and state management for all action types  
- **Supply-change implementation**: Specific handling of balance-affecting corporate actions
- **Technical rebase system**: Lazy migration and precision preservation
- **Consumer interface**: Reliable interface for external contracts and oracles

### Design Approach
- **Extensible framework**: Built to support future corporate action types beyond initial scope
- **Operational reliability**: Timing enforcement and execution windows for downstream certainty

## Implementation Roadmap

### PR 1: Minimal Diamond Facet Setup
**Goal**: Establish basic diamond facet architecture and prove integration works

**Key Deliverables**:
- Diamond facet integration with existing vault
- Basic facet contract with minimal functionality
- LibCorporateAction storage library with diamond storage pattern
- Stub implementation to demonstrate facet works

**Unit Testing Requirements**:
- Diamond storage pattern integration
- Facet function routing
- Basic storage operations
- Fuzz testing for storage patterns

### PR 2: Corporate Actions Framework Library
**Goal**: Implement core corporate action library with scheduling, timing, and state management

**Key Deliverables**:
- Complete LibCorporateAction with scheduling and state management
- Corporate action data structures and storage
- Execution window enforcement (4-hour deadline)
- State transition validation (SCHEDULED → IN_PROGRESS → COMPLETE/EXPIRED)
- Authorization integration framework
- Event emission for audit trails
- Library designed for pure testing without external dependencies

**Unit Testing Requirements**:
- State transition validation (fuzzed)
- Execution window timing enforcement
- Authorization permission checks
- Event emission correctness
- Storage consistency
- Fuzz testing for all library functions

### PR 3: Stock Split Implementation with Stub Outcomes
**Goal**: Implement stock splits as first corporate action type with stubbed execution

**Key Deliverables**:
- Stock split corporate action type implementation
- Query interfaces for external contracts
- Execution interfaces for corporate actions
- Stubbed outcome implementation (no actual rebasing yet)
- Complete corporate action lifecycle from schedule to execution
- Corporate action facet with full interface

**Unit Testing Requirements**:
- Stock split scheduling and validation
- Query interface functionality
- Execution interface correctness
- State transitions for real corporate action type
- Authorization integration
- Event emission for stock splits
- Fuzz testing for corporate action parameters

### PR 4: Sequential Rebase Implementation with Receipts
**Goal**: Implement actual rebasing logic with lazy migration and receipt coordination

**Key Deliverables**:
- Replace stub execution with real balance effects
- Version-based lazy migration system using OpenZeppelin v5 `_update` hook
- Sequential multiplier application with Rain float math
- Account migration for sender and recipient during transfers
- Balance rasterization during write operations
- Receipt coordination via manager relationship
- Shared library for common rebase logic between vault and receipts

**Unit Testing Requirements**:
- Migration trigger validation
- Sequential multiplier application correctness
- Balance rasterization accuracy
- Receipt coordination functionality
- Shared library operations
- Account version tracking
- Fuzz testing for multiplier calculations and migration scenarios

## System Integration

### Integration Testing
After all PRs complete:
- End-to-end corporate action lifecycle testing
- Mixed rebase and non-rebase action scenarios
- External contract integration simulation
- Receipt and vault balance consistency validation

### Fork Testing
Once contracts deployed:
- Real network deployment validation
- Integration with existing vault infrastructure
- Performance validation under realistic conditions