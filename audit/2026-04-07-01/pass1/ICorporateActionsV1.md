# A20 — Pass 1 (Security): ICorporateActionsV1

**File:** `src/interface/ICorporateActionsV1.sol` (77 lines)

## Evidence of thorough reading

**Interface:** `ICorporateActionsV1`

**Functions:**
- `scheduleCorporateAction(bytes32, uint64, bytes)` external returns (uint256) — line 19
- `cancelCorporateAction(uint256)` external — line 25
- `completedActionCount()` external view returns (uint256) — line 29
- `latestActionOfType(uint256)` external view — line 39
- `earliestActionOfType(uint256)` external view — line 51
- `nextOfType(uint256, uint256)` external view — line 62
- `prevOfType(uint256, uint256)` external view — line 73

**Types/errors/constants:** none.

## Findings

None. Interfaces have no executable surface; semantic concerns are flagged in Pass 5.
