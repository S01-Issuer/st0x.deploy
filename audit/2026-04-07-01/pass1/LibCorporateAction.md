# A21 — Pass 1 (Security): LibCorporateAction

**File:** `src/lib/LibCorporateAction.sol` (223 lines)

## Evidence of thorough reading

**Library:** `LibCorporateAction`

**Storage struct:** `CorporateActionStorage` — line 49
- `uint256 head` — line 51
- `uint256 tail` — line 53
- `CorporateActionNode[] nodes` — line 55
- `mapping(address => uint256) accountMigrationCursor` — line 58
- `mapping(uint256 => uint256) unmigrated` — line 65
- `uint256 totalSupplyLatestSplit` — line 69
- `bool totalSupplyBootstrapped` — line 72

**Functions:**
- `getStorage()` internal pure — line 76
- `resolveActionType(bytes32, bytes)` internal pure — line 88
- `schedule(uint256, uint64, bytes)` internal — line 103
- `cancel(uint256)` internal — line 158
- `countCompleted()` internal view — line 189
- `headNode()` internal view — line 201
- `tailNode()` internal view — line 210
- `head()` internal view — line 216
- `tail()` internal view — line 220

**Constants:**
- `CORPORATE_ACTION_STORAGE_LOCATION` (file scope) — line 10
- `SCHEDULE_CORPORATE_ACTION` — line 13
- `CANCEL_CORPORATE_ACTION` — line 16
- `STOCK_SPLIT_TYPE_HASH` — line 19
- `ACTION_TYPE_STOCK_SPLIT` — line 22

**Errors:**
- `EffectiveTimeInPast(uint64, uint256)` — line 25
- `ActionAlreadyComplete(uint256)` — line 28
- `ActionDoesNotExist(uint256)` — line 31
- `UnknownActionType(bytes32)` — line 35

## Findings

### A21-1 — `schedule()` accepts unbounded `bytes parameters` from authorized callers

**Severity:** LOW

**Location:** `src/lib/LibCorporateAction.sol:103-153`

`schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters)` writes `parameters` directly into storage at `s.nodes[actionIndex].parameters` with no upper-length bound. An authorized scheduler (or one that passes the authorizer's policy gate, which is currently coarse — see A01-1) could push arbitrarily large parameter blobs, billing the deployment with permanent storage cost and bloating the linked list's storage footprint. For known action types like stock splits the parameters are a single `Float` (~32 bytes), so a sane scheduler never approaches this; but defense-in-depth would set a reasonable cap (e.g., 1 KiB) and revert otherwise.

**Suggested fix:** see `.fixes/A21-1.md`.

### A21-2 — Cancellation silently invalidates outstanding cursors held by external callers

**Severity:** INFO

**Location:** `src/lib/LibCorporateAction.sol:158-186`

After `cancel(idx)`, the cancelled node has `prev = 0`, `next = 0`, `effectiveTime = 0`. A consumer that previously obtained `idx` from `nextOfType` and is iterating with `nextOfType(idx, ...)` will compute `s.nodes[idx].next == 0` and immediately receive 0 — losing visibility of the rest of the list past the cancelled node. There is no error or signal that `idx` is stale. Iteration consumers should re-fetch from `head` after a cancel; this is undocumented. INFO because the linked-list semantics for cancel are intentional, not a bug; documentation is the right remedy and is captured under Pass 3.

## Items deliberately not flagged

- ERC-7201 storage location matches the documented derivation (verified that the value ends in `00` per the `~bytes32(0xff)` mask, and the test `testStorageSlotCalculation` in `StoxCorporateActionsFacet.t.sol:109` performs the runtime equality check).
- Schedule/cancel linked-list manipulation: walked through schedule-into-empty, schedule-after-tail, schedule-mid-list, schedule-before-head, cancel-head, cancel-tail, cancel-mid — all maintain `head`/`tail`/`prev`/`next` consistency.
- The `s.nodes.length == 0` first-use sentinel push (line 114) correctly establishes index 0 as the "no node" sentinel.
- `countCompleted` walks via `nextOfType(_, max, COMPLETED)` which short-circuits at the first pending node — O(completed) not O(n).
- Bounds: `cancel` checks `actionIndex == 0 || actionIndex >= s.nodes.length` and re-checks `node.effectiveTime == 0` to catch sentinel/already-cancelled nodes.
