# Corporate Actions Implementation Plan

## Architecture Summary

### Core System
- **Diamond facet** adds corporate action functionality to existing vault
- **Version-based lazy migration** - accounts migrate to current version only when interacting
- **Sequential multiplier application** preserves computational precision for custodian compliance
- **OpenZeppelin v5 `_update` hook** handles migration as pre-step for all balance operations

### Key Design Decisions
- **Don't scale user input** - constant gas costs regardless of corporate action history
- **Lazy evaluation** - one-time migration cost per corporate action period, then efficient operations
- **Precision preservation** - sequential vs cumulative multipliers for computational correctness
- **User intent protection** - multipliers applied to stored balances, never user input amounts

### Integration Strategy
- **Vault integration** - corporate actions stored on token for single source of truth
- **Oracle compatibility** - external contracts can query vault directly for corporate action data

## Implementation Order

### PR 1: Diamond Facet Infrastructure
**Goal:** Set up the diamond facet and storage infrastructure

**Deliverables:**
- [ ] `src/lib/LibCorporateAction.sol` - storage library with diamond storage pattern
  - Corporate action struct definitions  
  - Version counter and multiplier mapping storage
  - Account version tracking storage
  - State transition validation functions (`startExecution`, `completeAction`, `expireAction`)
- [ ] `src/facet/CorporateActionFacet.sol` - basic facet contract 
  - Function selectors for corporate action operations
  - Basic view functions (length, getters, version queries)
  - Stub implementations for scheduling/execution
- [ ] Update diamond configuration to include new facet
- [ ] Tests: storage access, state transitions, version tracking, facet registration

**Key validations:**
- State transitions only allow valid changes (SCHEDULED→IN_PROGRESS→COMPLETE)
- Version counter increments correctly
- Account version tracking works properly
- Diamond storage pattern works correctly
- Facet functions are properly routed

### PR 2: Action Scheduling with Stub Dispatch
**Goal:** Add corporate action scheduling with placeholder execution

**Deliverables:**
- [ ] `CorporateActionFacet.scheduleSplit(uint256 numerator, uint256 denominator, uint256 effectiveTime)` 
- [ ] `CorporateActionFacet.scheduleReverseSplit(uint256 numerator, uint256 denominator, uint256 effectiveTime)`
- [ ] `CorporateActionFacet.execute(uint256 actionId)` - stub that just changes state to COMPLETE
- [ ] Execution window enforcement (4 hours after effectiveTime)
- [ ] Authorization via existing Authorizer pattern
- [ ] Query functions for external contracts:
  - `corporateActionsLength()`
  - `corporateActions(uint256 index)`
  - `getUpcomingActions()`
  - `getCompletedActions()`
- [ ] Events: `CorporateActionScheduled`, `CorporateActionExecuted`, `CorporateActionExpired`

**Key validations:**
- Can schedule split/reverse split with future effective times
- Authorization checks work correctly
- Execution window enforced (can't execute too early or too late)
- External query functions return correct data

### PR 3: Lazy Migration System  
**Goal:** Implement lazy migration system using OpenZeppelin v5's `_update` hook

**Deliverables:**
- [ ] Override `_update` hook with pre-step migration logic
- [ ] `_migrateAccount()` function that:
  - Checks if account version < global version
  - Applies sequential multipliers using Rain float math  
  - Sets account balance to computed effective balance
  - Advances account version to global version
- [ ] `LibCorporateAction.calculateMultiplier()` - converts action to multiplier
- [ ] `CorporateActionFacet.execute()` - real implementation that:
  - Increments global version counter  
  - Sets multiplier for new version based on corporate action
  - Updates corporate action state to COMPLETE
- [ ] Tests: migration triggering, sequential precision, gas cost validation

**Key validations:**
- Both sender and recipient migrated before balance changes
- Sequential multiplier application preserves precision behavior
- One-time migration cost per corporate action period  
- Subsequent operations have normal ERC20 gas costs
- User input amounts always preserved (no scaling contamination)
- Corporate action marked COMPLETE after successful version creation

### PR 4: System Integration & Validation
**Goal:** Complete integration testing and validation of corporate action system

**Deliverables:**
- [ ] Oracle compatibility verification:
  - External contracts can query upcoming corporate actions
  - Historical corporate action data accessible
  - Compatible with standard oracle query patterns
- [ ] Edge case handling:
  - Multiple actions scheduled for same time
  - Fractional share precision in sequential multiplier application  
  - Complex migration scenarios (dormant accounts, frequent traders)
- [ ] Complete system integration tests
- [ ] Gas optimization and performance benchmarking
- [ ] Documentation and examples for external integrators

**Key validations:**
- Oracles can detect upcoming version updates by querying vault
- Corporate action history preserved for external analysis
- Migration system works correctly with all vault operations
- User operations maintain constant gas costs regardless of corporate action history
- No regressions in vault functionality
- External contract integration works as expected

## Testing Strategy

### Unit Tests
- `LibCorporateAction`: state transitions, multiplier calculations
- `CorporateActionFacet`: authorization, scheduling, execution
- Storage: diamond storage access, data integrity

### Integration Tests  
- End-to-end: schedule split → execute → verify balances
- Oracle simulation: external contract querying rebase schedules
- Multi-action scenarios: several corporate actions in sequence

### Fork Tests
- Deploy facet to existing vault on testnet
- Verify oracle compatibility with real data
- Performance testing with large action histories

## Success Criteria

1. **External contracts can query vault directly** for upcoming/completed rebases
2. **State transitions are enforced** - no invalid state changes possible
3. **Authorization works** - only approved roles can schedule actions
4. **Execution windows enforced** - actions expire if not executed in time
5. **Compatible with oracle patterns** - matches standard interface expectations for external contracts
6. **No vault functionality regressions** - existing operations continue to work

## Risks & Mitigations

**Risk:** Diamond storage conflicts with existing vault storage
**Mitigation:** Use dedicated storage slots, extensive testing

**Risk:** Gas costs too high for complex corporate actions  
**Mitigation:** Optimize state updates, consider batch operations

**Risk:** Oracle integration issues
**Mitigation:** Test against real oracle implementations early

**Risk:** Timezone/timing issues with effective times
**Mitigation:** Use block.timestamp consistently, document timezone handling