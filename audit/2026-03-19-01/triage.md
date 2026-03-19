# Audit Triage — 2026-03-19-01

## Findings (LOW+)

| ID | Pass | Severity | Title | Status |
|---|---|---|---|---|
| P0-1 | 0 | MEDIUM | Deployment section lists stale suite names | FIXED — CLAUDE.md Deployment section updated with all 7 suite names |
| A02-1 | 1 | LOW | StoxUnifiedDeployer deployed with empty dependency list | FIXED — deps array added with both beacon set deployer addresses |
| A06-1 | 1 | LOW | Inherited renounceOwnership() could permanently disable beacon upgrades | DOCUMENTED — WARNING added to @dev NatSpec |
| A03-1 | 2 | LOW | 13 of 14 previously proposed StoxReceipt behavioral tests not added | DISMISSED — carried from 2026-03-18-01 A03-P2-1; all behavior is in ethgild Receipt base, testing deps is out of scope |
| A05-P2-3 | 2 | LOW | previewRedeem not tested | FIXED — testPreviewRedeemMatchesActual added |
| A05-P2-4 | 2 | LOW | maxWithdraw/maxRedeem not tested | FIXED — testMaxWithdrawMatchesDeposit and testMaxRedeemMatchesShares added |
| A05-P2-5 | 2 | LOW | No test for share price change after direct asset transfer | FIXED — testSharePriceIncreasesAfterDirectTransfer added |
| A06-P2-1 | 2 | LOW | No test coverage for ownership-gated beacon functions | FIXED — 5 tests added: upgradeTo, transferOwnership, access control, renounceOwnership |
| A07-P2-6 | 2 | LOW | No test verifies OARV deployer beacon configuration | FIXED — testOarvDeployerReceiptBeaconConfig and testOarvDeployerVaultBeaconConfig added |
| A10-P2-1 | 2 | LOW | 4 V1 creation bytecode constants never tested against compiled artifacts | DISMISSED — V1 bytecodes verified by on-chain fork tests against codehashes; contracts changed in V2 so compiled artifacts no longer match |
| A11-1 | 2 | LOW | V2 fork tests do not verify beacon owner/implementation on-chain | FIXED — beacon implementation and owner checks added to checkAllV2OnChain |
| A11-2 | 2 | LOW | V2 fork tests do not verify OARV deployer internal beacon state | FIXED — OARV receipt/vault beacon implementation and owner checks added to checkAllV2OnChain |
| A01-P3-3 | 3 | LOW | BuildPointers name param constraint undocumented | FIXED — NatSpec added to buildContractPointers documenting name constraint |
| A02-P3-1 | 3 | LOW | deploySuite internal function undocumented | FIXED — @dev and @param NatSpec added |
| A04-P3-3 | 3 | LOW | StoxReceiptVault missing @dev tag | FIXED — @dev added with inheritance, ICloneableV2, and Zoltu details |
| A05-P3-5 | 3 | LOW | name()/symbol() missing @return NatSpec | FIXED — @return tags added |
| A06-P3-2 | 3 | LOW | StoxWrappedTokenVaultBeacon missing @dev for constructor | FIXED — @dev added with constructor params, architecture role, deployment ordering |
| A09-P3-2 | 3 | LOW | Deployment event NatSpec says "successfully initialized" but emits before init | DISMISSED — carried from 2026-03-18-01 A07-P3-4; event only observable in successful transactions, NatSpec is accurate |
| A10-P3-1 | 3 | LOW | slither-disable annotation lacks explanatory comment | FIXED — explanatory comment added |
| A11-P3-1 | 3 | LOW | BEACON_INITIAL_OWNER NatSpec understates usage scope | FIXED — updated to mention all V2 beacons |
| A05-P4-1 | 4 | LOW | _-prefixed helper functions in test files | FIXED — renamed in all 3 test files |
| A05-P4-2 | 4 | LOW | MockERC20.sol uses ^0.8.25 pragma instead of =0.8.25 | FIXED — changed to =0.8.25 |
