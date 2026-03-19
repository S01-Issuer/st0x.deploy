# Pass 1: Security -- Deploy.sol

**Agent:** A02
**Date:** 2026-03-19
**File:** `script/Deploy.sol` (153 lines)

---

## Evidence of Thorough Reading

### Contract

| Name | Line | Base |
|---|---|---|
| `Deploy` | 37 | `Script` (forge-std) |

### Functions

| Function | Line | Visibility |
|---|---|---|
| `deploySuite(bytes memory creationCode, string memory contractPath, address expectedAddress, bytes32 expectedCodeHash, address[] memory dependencies)` | 40 | `internal` |
| `run()` | 82 | `public` |

### State Variables

| Variable | Line | Type |
|---|---|---|
| `depCodeHashes` | 38 | `mapping(string => mapping(address => bytes32))` |

### Constants (file-level)

| Constant | Line | Value |
|---|---|---|
| `DEPLOYMENT_SUITE_STOX_RECEIPT` | 27 | `keccak256("stox-receipt")` |
| `DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT` | 28 | `keccak256("stox-receipt-vault")` |
| `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT` | 29 | `keccak256("stox-wrapped-token-vault")` |
| `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON` | 30 | `keccak256("stox-wrapped-token-vault-beacon")` |
| `DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | 31-32 | `keccak256("stox-wrapped-token-vault-beacon-set-deployer")` |
| `DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | 33-34 | `keccak256("stox-offchain-asset-receipt-vault-beacon-set-deployer")` |
| `DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER` | 35 | `keccak256("stox-unified-deployer")` |

### Errors (file-level)

| Error | Line |
|---|---|
| `UnknownDeploymentSuite(bytes32 suite)` | 23 |

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

## Findings

### A02-1 [LOW] StoxUnifiedDeployer deployed with empty dependency list despite runtime dependencies

**Location:** `script/Deploy.sol` lines 141-148

**Description:** The `DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER` case passes `noDeps` (an empty `address[]`) to `deploySuite`. However, `StoxUnifiedDeployer.newTokenAndWrapperVault()` makes runtime calls to both `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` and `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` via their hardcoded addresses from `LibProdDeployV2`.

`LibRainDeploy.checkDependencies` verifies that all listed dependencies exist on each target network before proceeding with deployment. By omitting these two addresses from the dependency list, the deploy script will not verify their existence on the target chain before deploying the unified deployer. This could result in a successfully deployed `StoxUnifiedDeployer` whose sole function (`newTokenAndWrapperVault`) reverts on every call because the beacon set deployers it depends on are not yet deployed on that network.

The deployment itself succeeds (parameterless constructor, no constructor-time dependency), but the deployed contract is non-functional until its runtime dependencies are deployed separately -- and the script provides no guard against this ordering mistake.

**Impact:** Deploying `StoxUnifiedDeployer` to a chain where the beacon set deployers are absent produces a contract that cannot fulfill its purpose. While not exploitable in a security sense, it wastes deployer gas and the Zoltu nonce on that chain, and there is no on-chain recovery mechanism (the unified deployer has no storage or upgrade path).

---

### Security Review Summary

**Input validation:** `run()` reads `DEPLOYMENT_KEY` and `DEPLOYMENT_SUITE` via Forge cheatcodes (`vm.envUint`, `vm.envString`). These cheatcodes abort with a clear error if the variables are absent. The suite dispatch uses `keccak256` comparison against seven known constants; any unknown value triggers `revert UnknownDeploymentSuite(suite)`.

**Access controls:** `deploySuite` is `internal`, so only `run()` can invoke it. `run()` is `public` but gated behind Forge's broadcast mechanism -- it cannot be meaningfully called on-chain. No additional access control is needed for a deploy script.

**Private key handling:** The deployer private key is read from the environment (`vm.envUint("DEPLOYMENT_KEY")`) and passed to `LibRainDeploy.deployAndBroadcast`. It is never stored, logged, or emitted.

**Reentrancy:** Not applicable. This is a Forge script with no on-chain state.

**Arithmetic safety:** No arithmetic operations beyond loop iteration (bounded by `dependencies.length`, always small).

**Error handling:** All error paths use custom errors. `UnknownDeploymentSuite` catches any unrecognized suite. `LibRainDeploy` handles missing dependencies and codehash mismatches with its own custom errors.

**Assembly blocks:** None present.

**Rounding:** Not applicable.

**Dependency correctness (other suites):**
- `STOX_WRAPPED_TOKEN_VAULT_BEACON` correctly lists `STOX_WRAPPED_TOKEN_VAULT` as a dependency (the beacon's constructor references it as the implementation).
- `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` correctly lists `STOX_WRAPPED_TOKEN_VAULT_BEACON` (the deployer creates proxies pointing to the beacon).
- `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` correctly lists `STOX_RECEIPT` and `STOX_RECEIPT_VAULT` (referenced in its constructor config).
- `STOX_RECEIPT`, `STOX_RECEIPT_VAULT`, and `STOX_WRAPPED_TOKEN_VAULT` correctly have no dependencies (leaf contracts with parameterless constructors that don't reference other deployed contracts at construction time).

**Version imports:** The script correctly uses `LibProdDeployV2` (the current versioned constants library), consistent with versioning guidance.
