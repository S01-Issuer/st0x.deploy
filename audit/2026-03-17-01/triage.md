# Audit Triage — 2026-03-17-01

## Findings (LOW+)

| ID | Pass | Severity | Title | Status |
|---|---|---|---|---|
| P0-1 | 0 | MEDIUM | No CLAUDE.md project instructions | FIXED |
| P0-2 | 0 | LOW | README.md is minimal and lacks operational guidance | FIXED |
| A01-1 | 1 | LOW | String revert used instead of custom error (Deploy.sol:91) | FIXED |
| A04-1 | 1 | LOW | No zero-address validation for asset in initialize(bytes) | FIXED |
| A07-1 | 1 | LOW | Typo in constant name BEACON_INIITAL_OWNER | FIXED |
| A07-2 | 1 | LOW | Pragma ^0.8.25 inconsistent with =0.8.25 | DISMISSED — libs use caret intentionally for wider compatibility |
| P2-DEPLOY-1 | 2 | LOW | Zero test coverage for the Deploy script | FIXED |
| A04-2 | 2 | LOW | StoxWrappedTokenVault has zero unit-test coverage | FIXED |
| A05-P2-1 | 2 | LOW | No revert-propagation tests for downstream deployer failures | FIXED |
| A05-P2-2 | 2 | LOW | No integration test with real deployer contracts | FIXED — prod fork test verifies all deployed contracts |
| A06-2 | 2 | LOW | No test coverage for StoxWrappedTokenVaultBeaconSetDeployer | FIXED |
| A07-P2-1 | 2 | LOW | No on-chain verification for OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER | FIXED |
| A07-P2-2 | 2 | LOW | No on-chain verification for STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER | FIXED |
| A07-P2-3 | 2 | LOW | No test at all for BEACON_INITIAL_OWNER | DISMISSED — address is verified transitively via beacon codehash checks |
| A01-P3-1 | 3 | LOW | NatSpec propagates BEACON_INIITAL_OWNER typo | FIXED — resolved with A07-1 |
| A01-P3-2 | 3 | LOW | Internal deploy functions missing @param for deploymentKey | FIXED |
| A04-P3-1 | 3 | LOW | Typo "assuptions" in contract NatSpec | FIXED |
| A04-P3-2 | 3 | LOW | initialize(bytes) NatSpec does not document expected encoding | FIXED |
| A07-P3-1 | 3 | LOW | Library has no NatSpec documentation | FIXED |
| A07-P3-2 | 3 | LOW | No constant has a semantic NatSpec comment | FIXED |
| A07-P3-3 | 3 | LOW | PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1 has no comment | FIXED |
| P4-1 | 4 | LOW | Bare src/ import paths break submodule usage | FIXED |
| P4-2 | 4 | LOW | Mixed import path styles within single file | FIXED — resolved with P4-1 |
| P4-3 | 4 | LOW | Bare lib/ import path in test file | FIXED — removed unused import (P4-4) |
| P4-4 | 4 | LOW | Unused import of LibExtrospectBytecode | FIXED |
| P4-6 | 4 | LOW | Unused constant STOX_WRAPPED_TOKEN_VAULT | DISMISSED — deployment address constants serve as audit trail |
