# A27 — Pass 1 (Security): LibStockSplit

**File:** `src/lib/LibStockSplit.sol` (35 lines)

## Evidence of thorough reading

**Library:** `LibStockSplit`

**Functions:**
- `validateParameters(bytes)` internal pure — line 16
- `encodeParameters(Float)` internal pure — line 25
- `decodeParameters(bytes)` internal pure — line 32

**Errors:**
- `InvalidSplitMultiplier()` — line 8

## Findings

### A27-1 — `validateParameters` rejects only non-positive coefficients, allowing near-zero multipliers that wipe out all balances

**Severity:** MEDIUM

**Location:** `src/lib/LibStockSplit.sol:16-20`

```solidity
function validateParameters(bytes memory parameters) internal pure {
    Float multiplier = abi.decode(parameters, (Float));
    (int256 coefficient,) = LibDecimalFloat.unpack(multiplier);
    if (coefficient <= 0) revert InvalidSplitMultiplier();
}
```

The check rejects `coefficient == 0` and `coefficient < 0`. It does **not** reject:
- A multiplier with positive coefficient but very negative exponent (e.g. `1 × 10^-30`), which truncates every realistic per-account balance to 0.
- A multiplier with extremely large magnitude that would saturate or revert during float arithmetic on subsequent rebases.

Combined with A01-1 (the authorizer is given no per-action context and so cannot policy-gate by multiplier magnitude), this means a single authorized `scheduleCorporateAction` call with a near-zero `Float` permanently zeros every holder's balance once the action becomes complete. There is no withdrawal grace period — the moment `block.timestamp >= effectiveTime`, the next call to `balanceOf` returns 0 for everyone.

**Impact:** A compromised or fat-fingered `SCHEDULE_CORPORATE_ACTION` permission holder can wipe out the vault. The cancel window exists (cancels are only valid before `effectiveTime`), so a fast-acting governance can rescue, but for actions scheduled with short notice this is not a real safeguard.

**Suggested fix:** see `.fixes/A27-1.md`. Two layers:
1. Reject multipliers that would truncate a 1-token balance to 0 (i.e., `multiplier < 1e-18` for an 18-decimal token, or more generally enforce a minimum based on the float representation).
2. Reject multipliers whose magnitude would risk overflow when applied sequentially (concrete bound depends on the target token's decimals and realistic supply).

The cleanest minimum-multiplier check is to require that `LibDecimalFloat.toFixedDecimalLossy(multiplier, 0)` round to at least 1, OR document a sane absolute floor and ceiling on the (coefficient, exponent) pair.

### A27-2 — `decodeParameters` does not re-validate

**Severity:** INFO

**Location:** `src/lib/LibStockSplit.sol:32`

`decodeParameters` is called from `LibRebase.migratedBalance:51` and `LibTotalSupply.effectiveTotalSupply:93` to read stored multipliers from the linked list. Validation is only performed once, at `schedule()` time via `LibCorporateAction.resolveActionType` → `validateParameters`. As long as no other code path inserts nodes, this is safe. Worth noting in case a future facet method (e.g., a "force schedule" admin path) bypasses `resolveActionType`. INFO.

## Items deliberately not flagged

- `encodeParameters` and `decodeParameters` are symmetric `abi.encode`/`abi.decode` of a single `Float`. No length-prefix subtleties because Float is fixed-size.
- `abi.decode(parameters, (Float))` correctly reverts on malformed input.
