# Pass 4 — Other files (no quality findings beyond build warnings)

The following files have no Pass 4 findings beyond what is already captured in `_build_warnings.md`:

- `src/concrete/StoxReceiptVault.sol` (A03)
- `src/interface/ICorporateActionsV1.sol` (A20)
- `src/lib/LibCorporateActionNode.sol` (A22)
- `src/lib/LibERC20Storage.sol` (A23)
- `src/lib/LibStockSplit.sol` (A27)

## Unchanged files

Carried forward from `audit/2026-03-19-01/pass4/`. Two LOW findings from that run were FIXED:
- A05-P4-1 (`_`-prefixed test helper names) — FIXED
- A05-P4-2 (`MockERC20.sol` pragma) — FIXED

No new code-quality findings on unchanged files.
