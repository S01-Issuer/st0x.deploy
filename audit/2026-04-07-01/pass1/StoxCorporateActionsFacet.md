# A01 — Pass 1 (Security): StoxCorporateActionsFacet

**File:** `src/concrete/StoxCorporateActionsFacet.sol` (110 lines)

## Evidence of thorough reading

**Contract:** `StoxCorporateActionsFacet`

**Functions:**
- `completedActionCount()` external view — line 20
- `scheduleCorporateAction(bytes32, uint64, bytes)` external — line 25
- `cancelCorporateAction(uint256)` external — line 37
- `latestActionOfType(uint256)` external view — line 44
- `earliestActionOfType(uint256)` external view — line 59
- `nextOfType(uint256, uint256)` external view — line 74
- `prevOfType(uint256, uint256)` external view — line 89
- `_authorize(address, bytes32)` internal — line 106

**Events:**
- `CorporateActionScheduled(address indexed sender, uint256 indexed actionIndex, uint256 actionType, uint64 effectiveTime)` — line 14
- `CorporateActionCancelled(address indexed sender, uint256 indexed actionIndex)` — line 17

**Types/errors/constants:** none defined here (imports `SCHEDULE_CORPORATE_ACTION`, `CANCEL_CORPORATE_ACTION` from `LibCorporateAction`).

## Findings

### A01-1 — `_authorize` passes empty bytes data, losing per-action context

**Severity:** LOW

**Location:** `src/concrete/StoxCorporateActionsFacet.sol:108`

```solidity
auth.authorize(user, permission, "");
```

`IAuthorizeV1.authorize(address user, bytes32 permission, bytes calldata data)` accepts a `data` field for per-action context. The facet always passes `""`, so the authorizer is told only "user X has permission SCHEDULE_CORPORATE_ACTION" — it cannot distinguish "schedule a 2x stock split effective in 30 days" from "schedule a 1/1000 wipe-out split effective in one block." For high-impact actions like stock splits, the authorizer reasonably wants to apply per-call policy (size limits, multi-sig review, time-delay) but is denied the inputs needed.

**Impact:** Authorization is coarser than necessary. A compromised or sloppy issuer key with `SCHEDULE_CORPORATE_ACTION` permission can immediately schedule a wipe-out split without the authorizer being able to gate or rate-limit by action contents. This compounds the validation gap in `LibStockSplit.validateParameters` (see A27-1).

**Suggested fix:** Pass `abi.encode(typeHash, effectiveTime, parameters)` for `scheduleCorporateAction` and `abi.encode(actionIndex)` for `cancelCorporateAction`. Documented in `.fixes/A01-1.md`.

### A01-2 — Reentrancy via authorizer callback could front-run state writes

**Severity:** INFO

**Location:** `src/concrete/StoxCorporateActionsFacet.sol:30-34`

`scheduleCorporateAction` calls `_authorize` (an external call) before mutating linked-list storage. If a malicious authorizer reenters the facet via another vault function, the inner call's storage writes happen first, then the outer call's storage writes happen on the modified state. Today this isn't exploitable because (a) the authorizer is a trusted vault config and (b) the only side-effect is appending more action nodes — there's no fund movement. But the ordering is checks-effects-interactions inverted. INFO because the trust assumption holds.

## Items deliberately not flagged

- Direct calls to the facet (not via delegatecall) revert because `OffchainAssetReceiptVault(payable(address(this))).authorizer()` calls a non-existent selector on the facet itself. Not a security risk today.
- Out-of-bounds cursors passed by external callers cause Solidity panics — defensible default behavior.
- `_authorize` is `internal`; permissionless functions (`completedActionCount`, the four `*OfType` getters) are intentionally view-readable.
