# Pass 5 — Other files

The following files have no Pass 5 (intent verification) findings beyond what is already captured under earlier passes:

- `src/interface/ICorporateActionsV1.sol` (A20) — paired with A01-P5-1; the interface NatSpec is silent on completion semantics, captured under `pass3/ICorporateActionsV1.md::A20-P3-1`.
- `src/lib/LibCorporateActionNode.sol` (A22) — `nextOfType` / `prevOfType` names match behavior; the "0 = no match" sentinel convention is documented in NatSpec. No intent gap.
- `src/lib/LibERC20Storage.sol` (A23) — function names match what they do (raw slot reads/writes). The MEDIUM finding on layout drift is captured under Pass 1.
- `src/lib/LibRebase.sol` (A26) — `migratedBalance` name vs implementation gap is the CRITICAL Pass 1 finding A26-1. No separate Pass 5 entry; fixing A26-1 closes the intent gap.
- `src/lib/LibStockSplit.sol` (A27) — `validateParameters` name vs behavior gap is paired with A27-1 / A27-P3-1.
- `src/lib/LibTotalSupply.sol` (A28) — `effectiveTotalSupply`, `fold`, `onMint`, `onBurn`, `onAccountMigrated` all match their documented behavior. The bug exposed at integration time (A28-1) is a precondition violation by the caller, not a name/behavior mismatch within this library.

## Unchanged files

No new Pass 5 findings; carried forward from `audit/2026-03-19-01/`.
