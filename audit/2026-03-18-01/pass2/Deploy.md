# Pass 2 — Test Coverage: `script/Deploy.sol`

**Auditor:** A02
**Date:** 2026-03-18
**Prior finding resolved:** P2-DEPLOY-1 (zero test coverage) — CONFIRMED FIXED. `test/script/Deploy.t.sol` exists with two tests.

---

## Evidence of Thorough Reading

### `script/Deploy.sol`

**Contract:** `Deploy` (line 37) — extends `forge-std/Script.sol`

**Constants (file-level):**
| Name | Line |
|------|------|
| `DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET` | 24 |
| `DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET` | 28 |
| `DEPLOYMENT_SUITE_UNIFIED_DEPLOYER` | 31 |

**Errors (file-level):**
| Name | Line |
|------|------|
| `UnknownDeploymentSuite(bytes32 suite)` | 35 |

**Functions:**
| Name | Visibility | Line |
|------|-----------|------|
| `deployOffchainAssetReceiptVaultBeaconSet(uint256 deploymentKey)` | internal | 44 |
| `deployWrappedTokenVaultBeaconSet(uint256 deploymentKey)` | internal | 67 |
| `deployUnifiedDeployer(uint256 deploymentKey)` | internal | 86 |
| `run()` | public | 97 |

### `test/script/Deploy.t.sol`

**Contract:** `DeployTest` (line 14) — extends `forge-std/Test.sol`

**Functions:**
| Name | Visibility | Line |
|------|-----------|------|
| `testDeploymentSuiteConstants()` | external pure | 16 |
| `testUnknownDeploymentSuiteReverts()` | external | 26 |

---

## Coverage Analysis

### `run()` (line 97)
Called in `testUnknownDeploymentSuiteReverts()`. **Covered** for the error path only.

### `UnknownDeploymentSuite` error path (line 108)
Tested in `testUnknownDeploymentSuiteReverts()` with `vm.expectRevert(abi.encodeWithSelector(UnknownDeploymentSuite.selector, keccak256("unknown-suite")))`. **Covered** with correct specific revert expectation.

### `DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET` branch (line 101–102)
No test calls `run()` with `DEPLOYMENT_SUITE=offchain-asset-receipt-vault-beacon-set`. **Not covered.**

### `DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET` branch (line 103–104)
No test calls `run()` with `DEPLOYMENT_SUITE=wrapped-token-vault-beacon-set`. **Not covered.**

### `DEPLOYMENT_SUITE_UNIFIED_DEPLOYER` branch (line 105–106)
No test calls `run()` with `DEPLOYMENT_SUITE=unified-deployer`. **Not covered.**

### `deployOffchainAssetReceiptVaultBeaconSet(uint256)` (line 44)
Internal function, only reachable via `run()`. Not tested via any branch test. **Not covered.**

### `deployWrappedTokenVaultBeaconSet(uint256)` (line 67)
Internal function, only reachable via `run()`. Not tested via any branch test. **Not covered.**

### `deployUnifiedDeployer(uint256)` (line 86)
Internal function, only reachable via `run()`. Not tested via any branch test. **Not covered.**

### Suite constant correctness (lines 24, 28, 31)
All three constants verified by `testDeploymentSuiteConstants()`. **Covered.**

---

## Findings

### A02-1 — LOW: The three `run()` deployment suite branches are untested

**Severity:** LOW

**Location:** `script/Deploy.sol` lines 101–106 (`run()`), and the three internal deploy functions at lines 44, 67, 86.

**Description:**
`run()` dispatches to one of three internal functions based on the `DEPLOYMENT_SUITE` environment variable. The existing test file covers only the `UnknownDeploymentSuite` revert path and the constant values. None of the three successful dispatch branches (`offchain-asset-receipt-vault-beacon-set`, `wrapped-token-vault-beacon-set`, `unified-deployer`) are exercised by any test. This means the three internal deployment functions (`deployOffchainAssetReceiptVaultBeaconSet`, `deployWrappedTokenVaultBeaconSet`, `deployUnifiedDeployer`) have zero coverage through the `run()` entry point.

**Impact:**
A regression in branch dispatch (e.g., mistyped constant, wrong function called) would not be caught by the test suite. The constants are independently verified, but the wiring of `run()` to the correct branch is unverified.

**Evidence:**
- `test/script/Deploy.t.sol` contains only `testDeploymentSuiteConstants()` and `testUnknownDeploymentSuiteReverts()`.
- No test in any file under `test/` sets `DEPLOYMENT_SUITE` to a known-valid value and calls `deploy.run()`.
- The three internal functions are `internal` and not directly callable from tests, so coverage requires going through `run()`.

**Note on prior fix (P2-DEPLOY-1):**
P2-DEPLOY-1 identified zero test coverage. The fix was applied and the test file now exists with two tests. The `testUnknownDeploymentSuiteReverts` implementation in the actual file uses `abi.encodeWithSelector(UnknownDeploymentSuite.selector, keccak256("unknown-suite"))` which is correctly specific — better than the bare string `"Unknown deployment suite"` in the original proposed fix. The prior finding is resolved. This new finding (A02-1) identifies the remaining gap in branch coverage.
