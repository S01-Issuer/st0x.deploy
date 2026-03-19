# Pass 2 -- Test Coverage: `script/Deploy.sol`

**Auditor:** A02
**Date:** 2026-03-19
**Source file:** `script/Deploy.sol` (153 lines)
**Test file:** `test/script/Deploy.t.sol` (44 lines)

---

## Prior Finding Status

| Prior ID | Title | Status |
|---|---|---|
| A02-1 (2026-03-18) | Deploy suite branches untested | DISMISSED in triage -- deployment mechanics covered by `LibProdDeployV2` tests and `LibTestDeploy`; full script test requires multi-network RPC. Re-evaluated below. |

---

## Evidence of Thorough Reading

### `script/Deploy.sol`

**Contract:** `Deploy` (line 37) -- extends `Script` (forge-std)

**Error (file-level):**

| Name | Line |
|---|---|
| `UnknownDeploymentSuite(bytes32 suite)` | 23 |

**Constants (file-level):**

| Name | Line | Value |
|---|---|---|
| `DEPLOYMENT_SUITE_STOX_RECEIPT` | 27 | `keccak256("stox-receipt")` |
| `DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT` | 28 | `keccak256("stox-receipt-vault")` |
| `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT` | 29 | `keccak256("stox-wrapped-token-vault")` |
| `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON` | 30 | `keccak256("stox-wrapped-token-vault-beacon")` |
| `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | 31-32 | `keccak256("stox-wrapped-token-vault-beacon-set-deployer")` |
| `DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | 33-34 | `keccak256("stox-offchain-asset-receipt-vault-beacon-set-deployer")` |
| `DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER` | 35 | `keccak256("stox-unified-deployer")` |

**State Variables:**

| Name | Line | Type |
|---|---|---|
| `depCodeHashes` | 38 | `mapping(string => mapping(address => bytes32))` |

**Functions:**

| Name | Visibility | Line |
|---|---|---|
| `deploySuite(bytes memory creationCode, string memory contractPath, address expectedAddress, bytes32 expectedCodeHash, address[] memory dependencies)` | `internal` | 40 |
| `run()` | `public` | 82 |

### `test/script/Deploy.t.sol`

**Contract:** `DeployTest` (line 18) -- extends `Test` (forge-std)

**Imports (lines 7-16):**
- `Deploy` (the script contract)
- All 7 `DEPLOYMENT_SUITE_*` constants
- `UnknownDeploymentSuite` error

**Functions:**

| Name | Visibility | Line |
|---|---|---|
| `testDeploymentSuiteConstants()` | `external pure` | 20 |
| `testUnknownDeploymentSuiteReverts()` | `external` | 37 |

---

## Coverage Analysis

### Constants (lines 27-35)

All seven `DEPLOYMENT_SUITE_*` constants are imported and verified in `testDeploymentSuiteConstants()` (lines 21-33), each asserted equal to its `keccak256` string literal. **Covered.**

### `UnknownDeploymentSuite` error (line 23)

Tested in `testUnknownDeploymentSuiteReverts()` (lines 37-43). The test instantiates `Deploy`, sets `DEPLOYMENT_SUITE` to `"unknown-suite"`, and asserts revert with `abi.encodeWithSelector(UnknownDeploymentSuite.selector, keccak256("unknown-suite"))`. The selector and the encoded `suite` parameter are both verified. **Covered.**

### `run()` (line 82) -- error path

Called in `testUnknownDeploymentSuiteReverts()`. **Covered** for the `else` revert branch (line 150).

### `run()` (line 82) -- `DEPLOYMENT_SUITE_STOX_RECEIPT` branch (lines 86-93)

No test sets `DEPLOYMENT_SUITE=stox-receipt` and calls `run()`. **Not covered.**

### `run()` (line 82) -- `DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT` branch (lines 94-101)

No test sets `DEPLOYMENT_SUITE=stox-receipt-vault` and calls `run()`. **Not covered.**

### `run()` (line 82) -- `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT` branch (lines 102-109)

No test sets `DEPLOYMENT_SUITE=stox-wrapped-token-vault` and calls `run()`. **Not covered.**

### `run()` (line 82) -- `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON` branch (lines 110-119)

No test sets `DEPLOYMENT_SUITE=stox-wrapped-token-vault-beacon` and calls `run()`. **Not covered.**

### `run()` (line 82) -- `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` branch (lines 120-129)

No test sets the corresponding env var and calls `run()`. **Not covered.**

### `run()` (line 82) -- `DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` branch (lines 130-140)

No test sets the corresponding env var and calls `run()`. **Not covered.**

### `run()` (line 82) -- `DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER` branch (lines 141-148)

No test sets `DEPLOYMENT_SUITE=stox-unified-deployer` and calls `run()`. **Not covered.**

### `deploySuite(...)` (line 40)

Internal function, reachable only through `run()`. Since no successful dispatch branch of `run()` is tested, `deploySuite` has **zero coverage**.

### `depCodeHashes` mapping (line 38)

Passed to `LibRainDeploy.deployAndBroadcast` as a cross-deployment codehash cache. Never exercised because `deploySuite` is never called in tests. **Not covered.**

### Indirect coverage via `LibTestDeploy`

`test/lib/LibTestDeploy.sol` deploys the same contracts via `LibRainDeploy.deployZoltu` and asserts deterministic addresses match `LibProdDeployV2` constants. This validates that:
- Creation bytecodes produce the expected addresses
- The expected addresses in `LibProdDeployV2` are correct

However, `LibTestDeploy` does **not** exercise any code in `Deploy.sol` -- it is a parallel deployment path. The `deploySuite` function's logging, dependency checking, network iteration, and `deployAndBroadcast` call path are entirely untested.

---

## Findings

### A02-1 [INFO] All seven `run()` dispatch branches untested -- previously dismissed

**Severity:** INFO

**Location:** `script/Deploy.sol` lines 86-148 (`run()`), line 40 (`deploySuite`)

**Description:**
None of the seven successful dispatch branches of `run()` are exercised by any test. The `deploySuite` internal function has zero test coverage. Only the `UnknownDeploymentSuite` revert path is tested.

This was reported as A02-1 (LOW) in the 2026-03-18-01 audit and dismissed in triage with the rationale that deployment mechanics are covered by `LibProdDeployV2` tests and `LibTestDeploy`, and that full script testing requires multi-network RPC infrastructure.

**Triage rationale remains valid.** The `deploySuite` function is a thin wrapper around `LibRainDeploy.deployAndBroadcast` that:
1. Reads `DEPLOYMENT_KEY` from env
2. Gets supported networks from `LibRainDeploy.supportedNetworks()`
3. Logs diagnostic info via `console2`
4. Delegates to `LibRainDeploy.deployAndBroadcast`

The wiring correctness (which creation code, address, codehash, and dependencies are passed for each suite) would be the main value of branch-level tests. However, the arguments passed are all compile-time constants (`type(X).creationCode`, `LibProdDeployV2` constants), so a wiring error would likely manifest as a codehash mismatch at deployment time.

Re-raised as INFO for audit trail completeness. No action required.

### A02-2 [INFO] `depCodeHashes` mapping never tested

**Severity:** INFO

**Location:** `script/Deploy.sol` line 38

**Description:**
The `depCodeHashes` state variable is a `mapping(string => mapping(address => bytes32))` passed to `LibRainDeploy.deployAndBroadcast` as a cross-suite codehash cache. Since `deploySuite` is never called in tests, this mapping's accumulation behavior across multiple `deploySuite` calls within a single `Deploy` instance is untested.

In the current architecture, each `run()` invocation dispatches to exactly one suite, so the mapping is populated by at most one call. The caching behavior would only matter if `run()` were called multiple times on the same `Deploy` instance, which the script does not do. This is informational only.

---

## Summary

| Metric | Count |
|---|---|
| Functions in source | 2 (`deploySuite`, `run`) |
| Functions tested | 1 (`run`, error path only) |
| Constants in source | 7 |
| Constants tested | 7/7 |
| Errors in source | 1 |
| Errors tested | 1/1 |
| Branch coverage of `run()` | 1/8 (only the `else` revert) |
| Findings | 2 (both INFO) |

Both findings are INFO-level because the prior triage dismissal rationale remains valid: the `Deploy` script is a deployment-time orchestration wrapper whose correctness is validated by `LibTestDeploy` (address/bytecode verification) and `LibRainDeploy` (codehash/dependency verification at broadcast time). Testing the full `run()` dispatch branches would require multi-network RPC infrastructure that is impractical for unit tests.
