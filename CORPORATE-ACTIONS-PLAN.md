# Corporate Actions Implementation Plan

Four PRs, each building on the last. Every PR must have comprehensive unit tests with fuzz testing on all numeric and state-transition logic.

## PR 1: Diamond Facet Shell

Establish that the diamond facet architecture works with the existing vault. Nothing more.

**Scope**: A facet contract with a single placeholder function, `LibCorporateAction` with ERC-7201 namespaced storage containing just a version counter, and authorization wiring that distinguishes scheduling from execution permissions. The deliverable is a vault that successfully delegates a call to the facet and reads/writes diamond storage.

**Testing**: Verify facet routing works — calls to corporate action selectors hit the facet, calls to existing vault selectors still work. Fuzz the storage slot calculation to confirm no collisions with existing vault storage. Test authorization — scheduling calls from unauthorized addresses revert, execution calls from unauthorized addresses revert, correctly authorized calls succeed.

## PR 2: Framework and Scheduling

Implement the corporate action lifecycle from Component 2: scheduling, state machine, execution windows, and event emission. No actual corporate action types yet — the framework operates on a generic action struct with a type identifier and parameters blob.

**Scope**: `LibCorporateAction` grows to include action storage (sequential IDs, metadata, status), the state machine (SCHEDULED → IN_PROGRESS → COMPLETE, SCHEDULED → EXPIRED), and 4-hour execution window enforcement. The facet exposes scheduling and execution entry points. Events are emitted on every state transition.

**Testing**: Fuzz the state machine — generate random sequences of schedule/execute/expire calls and verify the state machine never reaches an invalid state. Fuzz timing — random effective times and execution timestamps, verifying the window is enforced correctly. Test that expired actions cannot be executed, that in-progress actions cannot be re-entered, that completed actions cannot be re-executed. Verify event emission matches state transitions exactly.

The library should be structured so its core logic can be tested in isolation without deploying the full vault. Pure functions where possible, internal functions tested through a thin harness contract.

## PR 3: Stock Splits with Stubbed Outcomes

Implement stock splits as the first concrete corporate action type (Component 3). The split schedules, validates its ratio, transitions through the lifecycle, and records its multiplier — but the multiplier is not yet applied to balances. Execution writes the multiplier to storage and completes successfully; actual balance effects come in PR 4.

**Scope**: Split ratio validation (must be expressible as Rain float without precision loss, reject problematic ratios), multiplier recording in the global action sequence, and the full query interface from Component 5. External contracts can now schedule a split, watch it execute, query action history, and read the pending multipliers — they just won't see balance changes yet.

**Testing**: Fuzz split ratio validation — generate random ratios and verify the validation correctly accepts clean ratios and rejects problematic ones. Test the complete lifecycle for a stock split from scheduling through execution. Test the query interface returns consistent results — schedule an action, query it, execute it, query it again, verify the returned data matches expectations. Fuzz the sequential ID assignment to confirm it is monotonically increasing and gap-free.

## PR 4: Rebase and Receipt Coordination

The final PR replaces the stub execution with real balance effects (Component 4) and adds receipt coordination.

**Scope**: The `_update` hook override that triggers migration, version tracking per account, sequential multiplier application using Rain float math, and the receipt system's matching migration logic via the manager interface. The effective balance view function also lands here.

This PR is the largest and most complex. If it proves too big during implementation, the receipt coordination can be split into a separate PR 5 — but the vault-side rebasing and the receipt-side rebasing share the same multiplier data and the same precision logic, so there is a strong argument for landing them together to ensure consistency from the start.

**Testing**: Fuzz the core migration logic heavily — generate random sequences of multipliers and random account interaction patterns, verify that all accounts converge to the same effective balance regardless of when they transact. Test the 1/3 × 3 × 1/3 × 3 = 99.999... case explicitly as a regression test. Fuzz transfers between accounts at different versions — verify both sides are migrated before the transfer executes. Test edge cases: zero balances through migration, near-precision-floor balances, near-overflow balances. Test receipt coordination: after a split, verify vault shares and receipt balances are proportionally consistent. Test atomicity: if receipt update reverts, the entire transaction reverts.

## Integration Testing

After all PRs merge, a final integration test suite covers end-to-end scenarios: schedule a split, execute it, transfer between a migrated and unmigrated account, mint new shares, burn shares, verify receipt consistency, query history from an external contract mock. Fork testing against deployed infrastructure follows once contracts are on a testnet.
