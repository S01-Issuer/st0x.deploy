# Pass 2 — Other files

## ICorporateActionsV1.sol (A20)

Pure interface; no executable surface, no test required.

## Unchanged source files

The 9 unchanged source files (`StoxReceipt`, `StoxWrappedTokenVault`, `StoxWrappedTokenVaultBeacon`, the two authorizer wrappers, the three deployers, the two `LibProdDeploy*` libraries) and the 9 generated `*.pointers.sol` files were last reviewed in `audit/2026-03-19-01/pass2/`. All LOW+ findings from that pass were triaged FIXED, FIXED, or DISMISSED:

- `A05-P2-3` previewRedeem — FIXED
- `A05-P2-4` maxWithdraw/maxRedeem — FIXED
- `A05-P2-5` share price after direct transfer — FIXED
- `A06-P2-1` ownership-gated beacon functions — FIXED
- `A07-P2-6` OARV deployer beacon configuration — FIXED
- `A10-P2-1` V1 creation bytecode constants — DISMISSED
- `A11-1` / `A11-2` V2 fork tests beacon owner / OARV deployer state — both FIXED

No changes to those files in this audit's branch range — see `pass1/_unchanged_files.md` for the diff verification. No new Pass 2 findings.
