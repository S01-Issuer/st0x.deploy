# A27 — Pass 3 (Documentation): LibStockSplit

**Source:** `src/lib/LibStockSplit.sol`

## Findings

### A27-P3-1 — `validateParameters` NatSpec says "positive non-zero" but the check is coefficient-only, missing the near-zero case

**Severity:** LOW (paired with A27-1)

**Location:** `src/lib/LibStockSplit.sol:13-20`

```solidity
/// @notice Validate that encoded parameters contain a valid stock split
/// multiplier. The multiplier must be a positive non-zero Rain float.
/// @param parameters ABI-encoded Float.
function validateParameters(bytes memory parameters) internal pure {
    Float multiplier = abi.decode(parameters, (Float));
    (int256 coefficient,) = LibDecimalFloat.unpack(multiplier);
    if (coefficient <= 0) revert InvalidSplitMultiplier();
}
```

"Positive non-zero Rain float" suggests the validation rejects all values that are mathematically ≤ 0 in real-number terms. But the check only inspects the coefficient — a Float with `coefficient = 1` and `exponent = -100` is mathematically `1e-100`, mathematically positive, but functionally indistinguishable from zero for any realistic balance. The doc and the implementation disagree on what "positive" means.

After A27-1's bound is added, the doc should be updated in the same change to describe the actual rejection rule (e.g., "must be at least 1e-18 and at most 1e18 in magnitude").

**Suggested fix:** see `.fixes/A27-P3-1.md` (depends on A27-1).
