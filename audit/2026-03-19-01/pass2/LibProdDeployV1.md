# Pass 2 -- Test Coverage: LibProdDeployV1

**Auditor:** A10
**Date:** 2026-03-19
**Source file:** `src/lib/LibProdDeployV1.sol`
**Test files examined:**
- `test/src/lib/LibProdDeployV1.t.sol`
- `test/src/lib/LibProdDeployV1V2.t.sol`
- `test/src/concrete/StoxWrappedTokenVaultV1.prod.base.t.sol`
- `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` (additional; references LibProdDeployV1 extensively)
- `test/src/concrete/StoxWrappedTokenVaultBeacon.t.sol` (additional; references BEACON_INITIAL_OWNER)

---

## Evidence of Thorough Reading

### Source: `src/lib/LibProdDeployV1.sol` (106 lines)

**Library:** `LibProdDeployV1` (line 10)

No functions. All members are constants:

| Constant | Type | Line |
|---|---|---|
| `BEACON_INITIAL_OWNER` | `address` | 14 |
| `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | `address` | 18 |
| `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | `address` | 23 |
| `STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION` | `address` | 30 |
| `PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` | `bytes32` | 34 |
| `STOX_UNIFIED_DEPLOYER` | `address` | 39 |
| `STOX_RECEIPT_IMPLEMENTATION` | `address` | 45 |
| `PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1` | `bytes32` | 48 |
| `PROD_STOX_RECEIPT_CREATION_BYTECODE_V1` | `bytes` | 53 |
| `STOX_RECEIPT_VAULT_IMPLEMENTATION` | `address` | 60 |
| `PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` | `bytes32` | 63 |
| `PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V1` | `bytes` | 68 |
| `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` | `bytes32` | 74 |
| `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1` | `bytes` | 79 |
| `PROD_STOX_WRAPPED_TOKEN_VAULT_CREATION_BYTECODE_V1` | `bytes` | 84 |
| `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` | `bytes32` | 89 |
| `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1` | `bytes` | 94 |
| `PROD_STOX_UNIFIED_DEPLOYER_CREATION_BYTECODE_V1` | `bytes` | 99 |
| `PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1` | `bytes32` | 104 |

Slither annotation: `slither-disable-next-line too-many-digits` on line 9 (applies to the library containing many hex literals).

### Test: `test/src/lib/LibProdDeployV1.t.sol` (24 lines)

**Contract:** `LibProdDeployV1Test` (line 11), inherits `Test`

| Function | Line | What it tests |
|---|---|---|
| `testCreationBytecodeStoxReceipt()` | 13 | `PROD_STOX_RECEIPT_CREATION_BYTECODE_V1` matches compiled artifact |
| `testCreationBytecodeStoxReceiptVault()` | 18 | `PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V1` matches compiled artifact |

### Test: `test/src/lib/LibProdDeployV1V2.t.sol` (49 lines)

**Contract:** `LibProdDeployV1V2Test` (line 15), inherits `Test`

| Function | Line | What it tests |
|---|---|---|
| `testStoxReceiptCodehashV1EqualsV2()` | 17 | `PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1` == V2 codehash |
| `testStoxReceiptVaultCodehashV1EqualsV2()` | 24 | `PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` == V2 codehash |
| `testStoxWrappedTokenVaultCodehashV1DiffersV2()` | 34 | `PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` != V2 codehash |
| `testStoxUnifiedDeployerCodehashV1DiffersV2()` | 43 | `PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1` != V2 codehash |

### Test: `test/src/concrete/StoxWrappedTokenVaultV1.prod.base.t.sol` (83 lines)

**Contract:** `StoxWrappedTokenVaultV1ProdBaseTest` (line 15), inherits `Test`

| Function | Line | What it tests |
|---|---|---|
| `_v1Beacon()` | 16 | Helper: forks Base, reads beacon from V1 deployer via old selector |
| `testProdV1ZeroAssetDoesNotRevert()` | 26 | V1 allows `initialize(bytes)` with `address(0)` -- behavioral difference from V2 |
| `testProdV1OldBeaconSelectorWorks()` | 39 | V1 deployer responds to old `I_STOX_WRAPPED_TOKEN_VAULT_BEACON()` selector; V2 selector fails |
| `testProdV1DeploymentEventAfterInitialize()` | 55 | V1 emits `Deployment` event after `initialize` (V2 emits before) |

Uses constants: `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` (address).

### Test: `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` (135 lines)

**Contract:** `StoxProdBaseTest` (line 24), inherits `Test`

| Function | Line | What it tests |
|---|---|---|
| `_checkAllOnChain()` | 26 | Fork test: validates all V1 addresses are deployed and codehashes match on-chain |
| `_checkUnchangedCreationBytecodes()` | 116 | `PROD_STOX_RECEIPT_CREATION_BYTECODE_V1` and `PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V1` match compiled artifacts |
| `testProdCreationBytecodes()` | 125 | Calls `_checkUnchangedCreationBytecodes()` |
| `testProdDeployBase()` | 130 | Calls `_checkAllOnChain()` (fork test) |

### Test: `test/src/concrete/StoxWrappedTokenVaultBeacon.t.sol` (29 lines)

**Contract:** `StoxWrappedTokenVaultBeaconTest` (line 13), inherits `Test`

| Function | Line | What it tests |
|---|---|---|
| `testBeaconConstructsWithExpectedConstants()` | 15 | V2 beacon construction (uses V2 constants only) |
| `testBeaconInitialOwnerConsistentAcrossVersions()` | 26 | `LibProdDeployV1.BEACON_INITIAL_OWNER` == `LibProdDeployV2.BEACON_INITIAL_OWNER` |

---

## Coverage Matrix

### Address constants

| Constant | On-chain fork test | Cross-version test | Artifact match test |
|---|---|---|---|
| `BEACON_INITIAL_OWNER` | Yes (owner checks in `_checkAllOnChain`) | Yes (V1==V2 in beacon test) | N/A |
| `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | Yes (deployed + codehash) | N/A | N/A |
| `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | Yes (deployed + codehash) | N/A | N/A |
| `STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION` | Yes (via beacon + codehash) | N/A | N/A |
| `STOX_UNIFIED_DEPLOYER` | Yes (deployed + codehash) | N/A | N/A |
| `STOX_RECEIPT_IMPLEMENTATION` | Yes (via beacon + codehash) | N/A | N/A |
| `STOX_RECEIPT_VAULT_IMPLEMENTATION` | Yes (via beacon + codehash) | N/A | N/A |

### Codehash constants

| Constant | On-chain fork test | Cross-version test |
|---|---|---|
| `PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` | Yes | Yes (V1 != V2) |
| `PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1` | Yes | Yes (V1 == V2) |
| `PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` | Yes | Yes (V1 == V2) |
| `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` | Yes | **No** |
| `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` | Yes | **No** |
| `PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1` | Yes | Yes (V1 != V2) |

### Creation bytecode constants

| Constant | Artifact match test | On-chain verification |
|---|---|---|
| `PROD_STOX_RECEIPT_CREATION_BYTECODE_V1` | Yes | No (but codehash is verified) |
| `PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V1` | Yes | No (but codehash is verified) |
| `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1` | **No** | No |
| `PROD_STOX_WRAPPED_TOKEN_VAULT_CREATION_BYTECODE_V1` | **No** | No |
| `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1` | **No** | No |
| `PROD_STOX_UNIFIED_DEPLOYER_CREATION_BYTECODE_V1` | **No** | No |

---

## Findings

### A10-1 [LOW] Four V1 creation bytecode constants are never tested against compiled artifacts

**Constants:**
- `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1` (line 79)
- `PROD_STOX_WRAPPED_TOKEN_VAULT_CREATION_BYTECODE_V1` (line 84)
- `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1` (line 94)
- `PROD_STOX_UNIFIED_DEPLOYER_CREATION_BYTECODE_V1` (line 99)

The test `_checkUnchangedCreationBytecodes()` in `StoxUnifiedDeployer.prod.base.t.sol` (lines 116-122) and `LibProdDeployV1Test` (lines 13-23) both verify only `PROD_STOX_RECEIPT_CREATION_BYTECODE_V1` and `PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V1` -- the contracts that are unchanged between V1 and V2. The remaining four creation bytecodes are stored but never verified against anything.

These four constants are for contracts that **changed** between V1 and V2. Because V1 source code is no longer in the repo, `vm.getCode()` cannot produce the V1 artifact for comparison. Nevertheless, the constants serve as an audit trail for reproducible redeployment and their correctness is indirectly supported by the on-chain codehash checks (if the creation bytecode were wrong, it would not produce the observed runtime codehash). However, a creation bytecode could theoretically contain extra trailing bytes that produce the correct runtime code but differ from the actual creation code used, and no test would catch this.

**Impact:** A corrupted or incorrect V1 creation bytecode constant for a changed contract would go undetected. Since these are historical records (V1 is superseded by V2), the practical risk is low -- they would only matter if someone attempted to redeploy V1 contracts.

**Recommendation:** Add fork tests that deploy from each stored creation bytecode and verify the resulting runtime codehash matches the corresponding `_BASE_CODEHASH_V1` constant. This confirms the creation bytecodes are self-consistent even when the original source is unavailable.

### A10-2 [INFO] Two V1 deployer codehashes lack cross-version comparison tests

**Constants:**
- `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` (line 74)
- `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` (line 89)

`LibProdDeployV1V2Test` compares receipt, receipt vault, wrapped token vault, and unified deployer codehashes between V1 and V2. The two beacon-set-deployer codehashes are verified on-chain (in `_checkAllOnChain()`) but have no V1-vs-V2 cross-version assertion.

This is informational because the beacon-set deployers embed immutable beacon addresses that differ between V1 and V2, so they are expected to differ. Adding an explicit `assertTrue(V1 != V2)` assertion (analogous to the wrapped-vault and unified-deployer tests) would document this expectation.

### A10-3 [INFO] `_v1Beacon()` helper in `StoxWrappedTokenVaultV1ProdBaseTest` uses `_` prefix

The helper function `_v1Beacon()` at line 16 of `StoxWrappedTokenVaultV1.prod.base.t.sol` uses a `_`-prefix naming style. Per `CLAUDE.md` naming conventions: "No meaningless `_`-prefixed helpers. All function names must be descriptive and convey what the function does."

The function forks Base and retrieves the V1 wrapped-token-vault beacon address. A more descriptive name like `forkBaseAndGetV1WrappedTokenVaultBeacon()` would satisfy the convention.

Note: `_checkAllOnChain()` and `_checkUnchangedCreationBytecodes()` in `StoxUnifiedDeployer.prod.base.t.sol` also use `_`-prefixes, but these names are descriptive of their purpose (the `_` prefix denotes internal helpers that are called by public test functions). The convention prohibits meaningless `_`-prefixed names, not all `_`-prefixed names. However, `_v1Beacon()` is borderline -- it does more than "get a beacon" (it also creates a fork).
