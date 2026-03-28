# Corporate Actions Implementation Plan

## Implementation Order

### PR 1: Diamond Facet Infrastructure
**Goal:** Set up the diamond facet and storage infrastructure

**Deliverables:**
- [ ] `src/lib/LibCorporateAction.sol` - storage library with diamond storage pattern
  - Corporate action struct definitions
  - Storage accessor functions
  - State transition validation functions (`startExecution`, `completeAction`, `expireAction`)
- [ ] `src/facet/CorporateActionFacet.sol` - basic facet contract 
  - Function selectors for corporate action operations
  - Basic view functions (length, getters)
  - Stub implementations for scheduling/execution
- [ ] Update diamond configuration to include new facet
- [ ] Tests: storage access, state transitions, facet registration

**Key validations:**
- State transitions only allow valid changes (SCHEDULED→IN_PROGRESS→COMPLETE)
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

### PR 3: Version-Based Multiplier Dispatch
**Goal:** Connect corporate action execution to version-based multiplier system

**Deliverables:**
- [ ] `LibCorporateAction.calculateMultiplier()` - converts action to multiplier using Rain float math
- [ ] `CorporateActionFacet.execute()` - real implementation that:
  - Increments global version counter
  - Sets multiplier for new version based on corporate action
  - Updates corporate action state to COMPLETE
- [ ] Integration with vault's lazy evaluation balance logic
- [ ] Tests: end-to-end split execution, multiplier precision, version advancement

**Key validations:**
- Split 2:1 creates correct multiplier (2.0) for new version
- Reverse split 1:10 creates correct multiplier (0.1) for new version  
- Balance reads apply sequential multipliers from account version to global version
- Write operations follow read-then-set-then-write sequence correctly
- Corporate action marked COMPLETE after successful version creation

### PR 4: Lazy Evaluation Integration
**Goal:** Ensure vault properly handles version-based lazy evaluation from corporate actions

**Deliverables:**
- [ ] Integration testing with lazy evaluation system and transfer logic
- [ ] Oracle compatibility verification:
  - External contracts can query upcoming corporate actions
  - Historical corporate action data accessible
  - Compatible with standard oracle query patterns
- [ ] Edge case handling:
  - Multiple actions scheduled for same time
  - Fractional share precision in sequential multiplier application
  - Transfer-triggered version updates and balance computation
- [ ] Gas optimization for lazy evaluation operations
- [ ] Documentation and examples for external integrators

**Key validations:**
- Oracles can detect upcoming version updates by querying vault
- Corporate action history preserved for external analysis
- Version-based balance computation works correctly with transfers
- Write operations properly sequence: read-then-set-then-write
- Account versions advance correctly after write operations
- No regressions in vault functionality

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