# Pass 3: Documentation -- `script/Deploy.sol`

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

| Name | Line | NatDoc |
|---|---|---|
| `UnknownDeploymentSuite(bytes32 suite)` | 23 | `@dev` on lines 21-22 |

### Constants (file-level)

| Name | Line | Value | NatDoc |
|---|---|---|---|
| `DEPLOYMENT_SUITE_STOX_RECEIPT` | 27 | `keccak256("stox-receipt")` | None |
| `DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT` | 28 | `keccak256("stox-receipt-vault")` | None |
| `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT` | 29 | `keccak256("stox-wrapped-token-vault")` | None |
| `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON` | 30 | `keccak256("stox-wrapped-token-vault-beacon")` | None |
| `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | 31-32 | `keccak256("stox-wrapped-token-vault-beacon-set-deployer")` | None |
| `DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | 33-34 | `keccak256("stox-offchain-asset-receipt-vault-beacon-set-deployer")` | None |
| `DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER` | 35 | `keccak256("stox-unified-deployer")` | None |

### State Variables

| Name | Line | Type | NatDoc |
|---|---|---|---|
| `depCodeHashes` | 38 | `mapping(string => mapping(address => bytes32))` | None |

### Functions

| Name | Visibility | Line | NatDoc |
|---|---|---|---|
| `deploySuite(bytes memory creationCode, string memory contractPath, address expectedAddress, bytes32 expectedCodeHash, address[] memory dependencies)` | `internal` | 40 | None |
| `run()` | `public` | 82 | `@notice` + `@dev` on lines 77-81 |

### Imports

| Symbol | Source |
|---|---|
| `Script`, `console2` | `forge-std/Script.sol` |
| `LibRainDeploy` | `rain.deploy/lib/LibRainDeploy.sol` |
| `LibProdDeployV2` | `src/lib/LibProdDeployV2.sol` |
| `StoxReceipt` | `src/concrete/StoxReceipt.sol` |
| `StoxReceiptVault` | `src/concrete/StoxReceiptVault.sol` |
| `StoxWrappedTokenVault` | `src/concrete/StoxWrappedTokenVault.sol` |
| `StoxWrappedTokenVaultBeacon` | `src/concrete/StoxWrappedTokenVaultBeacon.sol` |
| `StoxWrappedTokenVaultBeaconSetDeployer` | `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` |
| `StoxUnifiedDeployer` | `src/concrete/deploy/StoxUnifiedDeployer.sol` |
| `StoxOffchainAssetReceiptVaultBeaconSetDeployer` | `src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol` |

---

## Documentation Review

### Existing Documentation

1. **`UnknownDeploymentSuite` error (line 21-22):** Has a `@dev` comment explaining when it is thrown and what it means. Accurate and complete.

2. **Inline comment (line 25):** `// One suite per contract to avoid Zoltu factory nonce issues.` Explains the rationale for the constant-per-contract pattern. Accurate.

3. **`run()` function (lines 77-81):** Has `@notice` ("Entry point for the deployment script.") and `@dev` documenting the two required env vars (`DEPLOYMENT_KEY` and `DEPLOYMENT_SUITE`) with example suite values. The `@dev` lists `"stox-receipt"` and `"stox-wrapped-token-vault-beacon"` as examples with "etc." -- this is adequate since the constant names are self-documenting and the full set is visible immediately above.

### Missing Documentation

1. **Contract-level NatDoc:** The `Deploy` contract (line 37) has no `@title` or `@notice`. There is no contract-level documentation explaining what this script does, how it fits the deployment workflow, or its relationship to the Zoltu deterministic deployment strategy.

2. **`deploySuite` function (line 40):** This internal function has zero NatDoc. It is the core deployment orchestration function -- reads the deployer key, fetches supported networks, logs diagnostics, and delegates to `LibRainDeploy.deployAndBroadcast`. It has 5 parameters, none documented.

3. **`depCodeHashes` state variable (line 38):** No NatDoc. This mapping serves as a cross-deployment codehash cache passed to `LibRainDeploy.deployAndBroadcast`. Its purpose and semantics (network name -> address -> codehash) are not documented.

4. **File-level constants (lines 27-35):** The 7 `DEPLOYMENT_SUITE_*` constants have no individual NatDoc. The group comment on line 25 provides rationale but not per-constant documentation. Given their names are self-documenting and they are simple `keccak256` hashes of string literals, this is a minor gap.

---

## Findings

### A02-1 [LOW] `deploySuite` internal function has no NatDoc

**Location:** `script/Deploy.sol` line 40

**Description:**
The `deploySuite` function is the core deployment orchestration function. It accepts 5 parameters (`creationCode`, `contractPath`, `expectedAddress`, `expectedCodeHash`, `dependencies`), reads the deployer private key from the environment, fetches supported networks, logs diagnostic information, and delegates to `LibRainDeploy.deployAndBroadcast`.

None of this is documented. There is no `@dev` or `@notice` tag, no `@param` tags for the 5 parameters, and no indication of what side effects the function has (broadcasting transactions, logging). The function is `internal` so it does not appear in the ABI, but it is the primary logic of the script and deserves documentation explaining its purpose, parameters, and behavior.

### A02-2 [INFO] Contract `Deploy` has no contract-level NatDoc

**Location:** `script/Deploy.sol` line 37

**Description:**
The `Deploy` contract has no `@title`, `@notice`, or `@dev` tags. A contract-level comment explaining its role in the deployment pipeline (Zoltu deterministic deployer orchestration, one-suite-per-run dispatch) would aid readability and auditability. This is INFO because the file-level comments and `run()` NatDoc partially cover this information, but a `@title` would be conventional.

### A02-3 [INFO] `depCodeHashes` mapping has no NatDoc

**Location:** `script/Deploy.sol` line 38

**Description:**
The `depCodeHashes` state variable is a nested mapping (`string => mapping(address => bytes32)`) that serves as a cross-deployment codehash cache. Its purpose and key semantics are undocumented. This is INFO because the mapping is only consumed by `LibRainDeploy.deployAndBroadcast` and is not part of any external interface, but a `@dev` comment explaining its role as a network-keyed codehash cache would improve clarity.

### A02-4 [INFO] File-level constants lack individual NatDoc

**Location:** `script/Deploy.sol` lines 27-35

**Description:**
The 7 `DEPLOYMENT_SUITE_*` constants have no individual `@dev` tags. The group comment on line 25 explains the one-suite-per-contract rationale but does not describe what each constant represents. This is INFO because the constant names are fully self-documenting (`DEPLOYMENT_SUITE_STOX_RECEIPT` clearly maps to `keccak256("stox-receipt")`) and the keccak256 derivation is visible inline.

---

## Summary

| Metric | Count |
|---|---|
| Functions in source | 2 |
| Functions with NatDoc | 1/2 (`run` only) |
| Contract-level NatDoc | Missing |
| State variables with NatDoc | 0/1 |
| File-level constants with NatDoc | 0/7 (group comment present) |
| File-level errors with NatDoc | 1/1 |
| Findings | 4 (1 LOW, 3 INFO) |

The `run()` function has adequate documentation including env var requirements. The main gap is the `deploySuite` internal function which has no documentation at all despite being the core logic of the script.
