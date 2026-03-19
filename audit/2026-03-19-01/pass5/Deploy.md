# Pass 5: Correctness / Intent Verification -- `script/Deploy.sol`

**Agent:** A02
**Date:** 2026-03-19
**File:** `script/Deploy.sol` (153 lines)

---

## Evidence of Thorough Reading

### Contract

| Name | Line | Base |
|---|---|---|
| `Deploy` | 37 | `Script` (forge-std) |

### Error (file-level)

| Name | Line |
|---|---|
| `UnknownDeploymentSuite(bytes32 suite)` | 23 |

### Constants (file-level)

| Name | Line | Value |
|---|---|---|
| `DEPLOYMENT_SUITE_STOX_RECEIPT` | 27 | `keccak256("stox-receipt")` |
| `DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT` | 28 | `keccak256("stox-receipt-vault")` |
| `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT` | 29 | `keccak256("stox-wrapped-token-vault")` |
| `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON` | 30 | `keccak256("stox-wrapped-token-vault-beacon")` |
| `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | 31-32 | `keccak256("stox-wrapped-token-vault-beacon-set-deployer")` |
| `DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | 33-34 | `keccak256("stox-offchain-asset-receipt-vault-beacon-set-deployer")` |
| `DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER` | 35 | `keccak256("stox-unified-deployer")` |

### State Variables

| Name | Line | Type |
|---|---|---|
| `depCodeHashes` | 38 | `mapping(string => mapping(address => bytes32))` |

### Functions

| Name | Visibility | Line |
|---|---|---|
| `deploySuite(bytes, string, address, bytes32, address[])` | `internal` | 40 |
| `run()` | `public` | 82 |

---

## Correctness Verification

### 1. Suite constant values vs string literals

Each `DEPLOYMENT_SUITE_*` constant is `keccak256(...)` of a string literal. The `run()` function on line 83 computes `keccak256(bytes(vm.envString("DEPLOYMENT_SUITE")))` and compares against these constants. This is correct: the comparison domain matches.

Test coverage: `test/script/Deploy.t.sol:testDeploymentSuiteConstants` independently recomputes each `keccak256` and asserts equality for all 7 constants. Verified correct.

### 2. Suite dispatch -- creation code vs expected address/codehash correspondence

Each `if`/`else if` branch passes:
- `type(ContractName).creationCode` -- the creation code for the contract
- The contract's source path string
- `LibProdDeployV2.CONSTANT` -- the expected Zoltu address for that contract
- `LibProdDeployV2.CONSTANT_CODEHASH` -- the expected codehash for that contract

Verified all 7 branches use consistent constant names from `LibProdDeployV2`:
- **stox-receipt** (L86-93): `StoxReceipt` creation code, `STOX_RECEIPT`, `STOX_RECEIPT_CODEHASH` -- correct.
- **stox-receipt-vault** (L94-101): `StoxReceiptVault` creation code, `STOX_RECEIPT_VAULT`, `STOX_RECEIPT_VAULT_CODEHASH` -- correct.
- **stox-wrapped-token-vault** (L102-109): `StoxWrappedTokenVault` creation code, `STOX_WRAPPED_TOKEN_VAULT`, `STOX_WRAPPED_TOKEN_VAULT_CODEHASH` -- correct.
- **stox-wrapped-token-vault-beacon** (L110-119): `StoxWrappedTokenVaultBeacon` creation code, `STOX_WRAPPED_TOKEN_VAULT_BEACON`, `STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH`, deps=[`STOX_WRAPPED_TOKEN_VAULT`] -- correct. The beacon's constructor references `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT` as the implementation, so this dependency is required.
- **stox-wrapped-token-vault-beacon-set-deployer** (L120-129): deps=[`STOX_WRAPPED_TOKEN_VAULT_BEACON`] -- correct. The deployer creates `BeaconProxy` pointing at the beacon.
- **stox-offchain-asset-receipt-vault-beacon-set-deployer** (L130-140): deps=[`STOX_RECEIPT`, `STOX_RECEIPT_VAULT`] -- correct. The deployer's constructor uses these as implementation addresses.
- **stox-unified-deployer** (L141-148): `noDeps` -- discussed below.

### 3. Contract path strings vs actual source paths

All 7 contract path strings match the actual source file structure:
- `"src/concrete/StoxReceipt.sol:StoxReceipt"` -- matches `src/concrete/StoxReceipt.sol`.
- `"src/concrete/StoxReceiptVault.sol:StoxReceiptVault"` -- matches `src/concrete/StoxReceiptVault.sol`.
- `"src/concrete/StoxWrappedTokenVault.sol:StoxWrappedTokenVault"` -- matches.
- `"src/concrete/StoxWrappedTokenVaultBeacon.sol:StoxWrappedTokenVaultBeacon"` -- matches.
- `"src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol:StoxWrappedTokenVaultBeaconSetDeployer"` -- matches.
- `"src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol:StoxOffchainAssetReceiptVaultBeaconSetDeployer"` -- matches.
- `"src/concrete/deploy/StoxUnifiedDeployer.sol:StoxUnifiedDeployer"` -- matches.

### 4. Dependency arrays

Deployment via Zoltu uses the Zoltu factory's nonce-based address derivation. Dependencies listed in Deploy.sol are checked by `LibRainDeploy.checkDependencies` to ensure they exist on-chain before deploying. This is a pre-deployment safety check, not a compile-time dependency.

- `StoxReceipt`: `noDeps` -- correct. Parameterless constructor, no on-chain references.
- `StoxReceiptVault`: `noDeps` -- correct. Parameterless constructor (`_disableInitializers()` only), no on-chain references.
- `StoxWrappedTokenVault`: `noDeps` -- correct. Constructor only calls `_disableInitializers()`.
- `StoxWrappedTokenVaultBeacon`: deps=[`STOX_WRAPPED_TOKEN_VAULT`] -- correct. Constructor arg references this address.
- `StoxWrappedTokenVaultBeaconSetDeployer`: deps=[`STOX_WRAPPED_TOKEN_VAULT_BEACON`] -- correct. Runtime dependency (BeaconProxy constructor arg).
- `StoxOffchainAssetReceiptVaultBeaconSetDeployer`: deps=[`STOX_RECEIPT`, `STOX_RECEIPT_VAULT`] -- correct. Constructor config references both.
- `StoxUnifiedDeployer`: `noDeps` -- see finding A02-P5-1 below.

### 5. `deploySuite` function correctness

The function (L40-75):
1. Fetches supported networks via `LibRainDeploy.supportedNetworks()` -- correct.
2. Reads `DEPLOYMENT_KEY` from env -- correct, documented in `run()` NatSpec.
3. Logs diagnostic info including dependency addresses and their on-chain code lengths/codehashes -- correct diagnostic approach.
4. Delegates to `LibRainDeploy.deployAndBroadcast` with all parameters -- correct forwarding.

### 6. Error condition: unknown suite

Line 149-150: `revert UnknownDeploymentSuite(suite)` in the final `else` block. This correctly passes the hashed suite value to the error, enabling diagnosis.

Test coverage: `test/script/Deploy.t.sol:testUnknownDeploymentSuiteReverts` sets `DEPLOYMENT_SUITE` to `"unknown-suite"` and expects `UnknownDeploymentSuite(keccak256("unknown-suite"))`. Verified correct.

### 7. NatSpec vs implementation

`run()` NatSpec (L77-81) documents:
- "Entry point for the deployment script" -- correct.
- Requires `DEPLOYMENT_KEY` env var -- correct (read on L48).
- Requires `DEPLOYMENT_SUITE` env var -- correct (read on L83).
- Lists example suites -- matches actual constants.

---

## Findings

### A02-P5-1 [LOW] StoxUnifiedDeployer deployed with empty dependency list

**Location:** `script/Deploy.sol` lines 141-148

**Description:**

The `DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER` case (L141-148) passes `noDeps` to `deploySuite`. However, `StoxUnifiedDeployer.newTokenAndWrapperVault()` makes runtime calls to both `LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` and `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER`.

While `StoxUnifiedDeployer` itself has a parameterless constructor (no compile-time dependencies), and Zoltu deployment will succeed regardless of whether these addresses have code, the purpose of the dependency check is to ensure that contracts deployed via this script will be functional on the target chain. Deploying `StoxUnifiedDeployer` to a chain where the beacon set deployers do not yet exist would result in a deployed-but-non-functional contract.

This is a deployment safety gap, not a correctness bug -- the contract would deploy successfully but `newTokenAndWrapperVault` would revert at runtime.

**Note:** This finding was previously identified in Pass 1 as A02-1 with a proposed fix in `.fixes/A02-1.md`. Re-confirmed here during correctness verification.

### A02-P5-2 [INFO] No test coverage for individual suite happy paths

**Location:** `test/script/Deploy.t.sol`

**Description:**

The test file covers:
1. Suite constant value correctness (all 7)
2. Unknown suite revert

But no test exercises a valid deployment suite through `run()` to verify that the creation code, expected address, and expected codehash are consistent and that `deploySuite` correctly orchestrates the deployment. This is understandable because the actual deployment requires the Zoltu factory and multi-chain RPC configuration, which are difficult to set up in unit tests. The fork tests in `test/src/lib/LibProdDeployV2.t.sol` provide some coverage by verifying that deployed on-chain contracts match the expected addresses and codehashes.

This is INFO because the per-suite orchestration is straightforward (each branch is a simple function call with constant arguments) and the fork tests provide indirect verification.

---

## Summary

| Check | Result |
|---|---|
| Constants match string literals | Correct (7/7), test-covered |
| Creation code matches contract | Correct (7/7) |
| Contract paths match filesystem | Correct (7/7) |
| Expected address/codehash from LibProdDeployV2 | Correct (7/7) |
| Dependencies match constructor/runtime needs | 6/7 correct; StoxUnifiedDeployer missing runtime deps (A02-P5-1) |
| Error conditions | Correct, test-covered |
| NatSpec vs implementation | Consistent |
| Findings | 1 LOW (pre-existing), 1 INFO |
