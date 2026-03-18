# Pass 2: Test Coverage — A07: LibProdDeploy.sol

## Evidence of Thorough Reading

**File:** `src/lib/LibProdDeploy.sol` (24 lines, constants-only library, no functions)

**All 6 constants traced through source and test code:**

| # | Constant | Line | Used in Source | Used in Test | On-Chain Verified |
|---|---|---|---|---|---|
| 1 | `BEACON_INIITAL_OWNER` | 7 | `script/Deploy.sol:42,60` | None | No |
| 2 | `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | 10-11 | `StoxUnifiedDeployer.sol:33` | Mock target only | No |
| 3 | `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | 14 | `StoxUnifiedDeployer.sol:36` | Mock target only | No |
| 4 | `STOX_WRAPPED_TOKEN_VAULT` | 17 | None | None | No |
| 5 | `STOX_UNIFIED_DEPLOYER` | 20 | None | Prod test:21 | Yes (codehash) |
| 6 | `PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1` | 22-23 | None | Prod test:16,21 | Yes (codehash) |

## Findings

### A07-P2-1: No on-chain verification for OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER [LOW]

The address is used in production (`StoxUnifiedDeployer.sol:33`) but never verified against on-chain state. The unit test only mocks it via `vm.etch`. If the address were wrong, production would call a non-existent contract. A fork test should verify non-zero code at this address on Base.

### A07-P2-2: No on-chain verification for STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER [LOW]

Same gap as A07-P2-1. Used in production (`StoxUnifiedDeployer.sol:36`) but only mocked in tests.

### A07-P2-3: No test at all for BEACON_INIITAL_OWNER [LOW]

Used in `script/Deploy.sol` as `initialOwner` for both beacon deployers. No test verifies this address — not even that it has an EOA or is the actual on-chain beacon owner.

### A07-P2-4: No test for STOX_WRAPPED_TOKEN_VAULT (dead code) [INFO]

Defined but never referenced in source or tests. Flagged as dead code in Pass 1 (A07-4).
