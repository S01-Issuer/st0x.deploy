# A01 — Pass 2 (Test Coverage): StoxCorporateActionsFacet

**Source:** `src/concrete/StoxCorporateActionsFacet.sol` (110 lines)
**Tests:** `test/src/concrete/StoxCorporateActionsFacet.t.sol` (318 lines)

## What is covered

The test file does an excellent job exercising the linked-list semantics through the `LibHarness` (a simple contract that exposes `LibCorporateAction` / `LibCorporateActionNode` directly) and proves delegatecall routing works through the `DelegatecallHarness` for `completedActionCount()` only:

- `testCompletedActionCountInitiallyZero` — facet via delegatecall returns 0
- `testFacetRoutingViaDelegatecall` — same assertion, named differently
- `testStorageSlotCalculation` — verifies the ERC-7201 slot constant matches the runtime derivation
- `testAuthPermissionConstants` — keccak hashes for SCHEDULE/CANCEL permissions
- `testResolveActionTypeRevertsUnknown` — `UnknownActionType` revert path
- `testCountCompletedReturnsZero` / `testCountCompletedAfterComplete`
- `testScheduleSingleAction` / `testScheduleReturnsOneBased` / `testScheduleTimeOrdering` / `testSchedulePastReverts`
- `testCancelUnlinks` / `testCancelCompleteReverts` / `testCancelNonExistentReverts` / `testCancelMiddleMaintainsIntegrity`
- `testNextOfTypeCompletedEmpty` / `testNextOfTypeCompletedFilters` / `testNextOfTypeAll` / `testNextOfTypePending`
- `testPrevOfType` (ALL filter only)
- `testFuzzInsertionOrdering` (1–20 nodes, asserts non-decreasing effectiveTime)

## Findings

### A01-P2-1 — `scheduleCorporateAction` and `cancelCorporateAction` external entry points are never tested through the facet (auth path uncovered)

**Severity:** LOW

**Location:** `test/src/concrete/StoxCorporateActionsFacet.t.sol` (entire file)

The test file always calls `libHarness.schedule(...)` and `libHarness.cancel(...)` to manipulate the linked list. It never calls `facetViaHarness.scheduleCorporateAction(...)` or `facetViaHarness.cancelCorporateAction(...)`. Consequence: the `_authorize` codepath at `StoxCorporateActionsFacet.sol:106-109` is never executed in tests. A regression that breaks the `IAuthorizeV1.authorize` call (e.g., signature drift in ethgild's interface, accidentally hardcoded `address(0)` for authorizer, accidentally calling the wrong selector) would not be caught.

The test infrastructure already has a `DelegatecallHarness` and a way to simulate the vault. What's missing is a mock authorizer (or a forge-mocked `OffchainAssetReceiptVault.authorizer()` return) that lets the facet's `scheduleCorporateAction` complete its auth call. With a mock authorizer that allows everything, the facet's external schedule/cancel can be exercised end-to-end including the event emission.

**Suggested fix:** see `.fixes/A01-P2-1.md`. Adds a mock-authorizer harness wired into the delegatecall test setUp, plus tests for: (a) successful schedule via the facet emits `CorporateActionScheduled` and returns the right index, (b) successful cancel via the facet emits `CorporateActionCancelled`, (c) authorizer revert propagates as expected.

### A01-P2-2 — Facet event emissions (`CorporateActionScheduled`, `CorporateActionCancelled`) are never asserted

**Severity:** LOW

**Location:** facet `lines 14, 17` (event definitions); test file (no `vm.expectEmit`)

`vm.expectEmit` is not used anywhere in the facet test file. The schedule/cancel events are part of the public API (indexed by sender and actionIndex, used for offchain indexing) and have never been asserted. Naming, indexed-ness, and parameter order/values are all unverified. Bundled with the fix for A01-P2-1.

### A01-P2-3 — The four external traversal getters on the facet (`latestActionOfType`, `earliestActionOfType`, `nextOfType`, `prevOfType`) are not exercised through the facet

**Severity:** LOW

**Location:** facet `lines 44-101`; test file uses `libHarness.nextOfType` / `libHarness.prevOfType` only

These are PR6's headline additions for oracle integration. The tests confirm `LibCorporateActionNode.nextOfType` / `prevOfType` work but never go through the facet wrapper, which:

1. Decodes the returned cursor into `(cursor, actionType, effectiveTime)` tuple via a storage read.
2. Returns zeros for the actionType / effectiveTime fields when cursor is 0.
3. Uses `CompletionFilter.ALL` (the choice flagged in A01 Pass 5).

If the facet's wrapping of the lib result drifts (e.g., reads `node.actionType` from the wrong storage layout, or returns wrong default for empty), tests would not catch it. Also, oracle integrators reading via `(cursor, actionType, effectiveTime)` get a triple where each field needs separate verification — currently no test asserts the triple shape.

**Suggested fix:** see `.fixes/A01-P2-3.md`.

### A01-P2-4 — `prevOfType` is only tested with `CompletionFilter.ALL`

**Severity:** LOW

**Location:** `test/src/concrete/StoxCorporateActionsFacet.t.sol:262-277`

`testPrevOfType` exercises `CompletionFilter.ALL`. The COMPLETED and PENDING branches of `prevOfType` (specifically the `if (filter == CompletionFilter.PENDING && isCompleted) break;` early-out at line 95 of LibCorporateActionNode) are never executed. `nextOfType` has all three filters tested; `prevOfType` should have parity.

**Suggested fix:** see `.fixes/A01-P2-4.md`.
