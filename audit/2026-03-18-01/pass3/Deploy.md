# Pass 3: Documentation — script/Deploy.sol

**Agent:** A02
**Date:** 2026-03-18
**File:** `script/Deploy.sol` (103 lines)

---

## Evidence of Thorough Reading

### Contract

| Name | Line | Base |
|------|------|------|
| `Deploy` | 35 | `Script` (forge-std) |

### Functions

| Function | Line | Visibility |
|----------|------|------------|
| `deployOffchainAssetReceiptVaultBeaconSet(uint256 deploymentKey)` | 42 | `internal` |
| `deployWrappedTokenVaultBeaconSet(uint256 deploymentKey)` | 64 | `internal` |
| `deployUnifiedDeployer(uint256 deploymentKey)` | 78 | `internal` |
| `run()` | 89 | `public` |

### File-level constants

| Constant | Line | Value |
|----------|------|-------|
| `DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET` | 22–23 | `keccak256("offchain-asset-receipt-vault-beacon-set")` |
| `DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET` | 26 | `keccak256("wrapped-token-vault-beacon-set")` |
| `DEPLOYMENT_SUITE_UNIFIED_DEPLOYER` | 29 | `keccak256("unified-deployer")` |

### File-level errors

| Error | Line |
|-------|------|
| `UnknownDeploymentSuite(bytes32 suite)` | 33 |

### Imports

| Symbol | Source |
|--------|--------|
| `Script` | `forge-std/Script.sol` |
| `OffchainAssetReceiptVaultBeaconSetDeployer`, `OffchainAssetReceiptVaultBeaconSetDeployerConfig` | `ethgild/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol` |
| `LibProdDeployV1` | `src/lib/LibProdDeployV1.sol` |
| `StoxReceipt` | `src/concrete/StoxReceipt.sol` |
| `StoxReceiptVault` | `src/concrete/StoxReceiptVault.sol` |
| `StoxWrappedTokenVaultBeaconSetDeployer` | `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` |
| `StoxWrappedTokenVault` | `src/concrete/StoxWrappedTokenVault.sol` |
| `StoxWrappedTokenVaultBeacon` | `src/concrete/StoxWrappedTokenVaultBeacon.sol` |
| `StoxUnifiedDeployer` | `src/concrete/deploy/StoxUnifiedDeployer.sol` |
| `LibRainDeploy` | `rain.deploy/lib/LibRainDeploy.sol` |

---

## Prior Audit Fix Verification

### A01-P3-1 (typo `BEACON_INIITAL_OWNER` in NatSpec)

**Status: FIXED.**

The prior version of `deployOffchainAssetReceiptVaultBeaconSet`'s NatSpec referenced the constant name in prose, introducing the typo. The current NatSpec (lines 36–41) has been rewritten to describe the Zoltu deployment mechanism without mentioning the constant name. The typo no longer appears anywhere in the file.

### A01-P3-2 (missing `@param deploymentKey` on internal functions)

**Status: FIXED.**

All three internal functions now carry a `@param deploymentKey` tag:
- `deployOffchainAssetReceiptVaultBeaconSet`: lines 40–41
- `deployWrappedTokenVaultBeaconSet`: lines 62–63
- `deployUnifiedDeployer`: lines 76–77

---

## Documentation Review

### NatSpec coverage

| Element | NatSpec present | Notes |
|---------|----------------|-------|
| `DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET` | `@dev` (line 20–21) | Adequate for a file-level constant |
| `DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET` | `@dev` (line 25) | Adequate |
| `DEPLOYMENT_SUITE_UNIFIED_DEPLOYER` | `@dev` (line 28) | Adequate |
| `UnknownDeploymentSuite(bytes32 suite)` | `@dev` (lines 31–32) | No `@param suite` |
| `deployOffchainAssetReceiptVaultBeaconSet` | `@notice` + `@param` | Complete |
| `deployWrappedTokenVaultBeaconSet` | `@notice` + `@param` | Complete |
| `deployUnifiedDeployer` | `@notice` + `@param` | Complete |
| `run()` | `@notice` only | Missing `@dev` on env vars read |

### Accuracy of existing documentation

**`deployOffchainAssetReceiptVaultBeaconSet` (lines 36–41):**

> "Implementations (StoxReceipt, StoxReceiptVault) are deployed via Zoltu for deterministic addresses. The beacon set deployer itself uses `new` because it is an upstream (ethgild) contract with constructor args."

Implementation uses `LibRainDeploy.deployZoltu` for `StoxReceipt` and `StoxReceiptVault` (lines 45–46), and `new OffchainAssetReceiptVaultBeaconSetDeployer(...)` (lines 48–54). The explanation that `new` is required "because it is an upstream (ethgild) contract with constructor args" is accurate — the Zoltu pattern requires no constructor args for determinism, while `OffchainAssetReceiptVaultBeaconSetDeployer` takes a `OffchainAssetReceiptVaultBeaconSetDeployerConfig` struct. No inaccuracy.

**`deployWrappedTokenVaultBeaconSet` (lines 59–63):**

> "All three contracts (implementation, beacon, deployer) are deployed via Zoltu for deterministic addresses."

Implementation deploys three contracts via `LibRainDeploy.deployZoltu`: `StoxWrappedTokenVault`, `StoxWrappedTokenVaultBeacon`, `StoxWrappedTokenVaultBeaconSetDeployer` (lines 67–69). Count and mechanism are accurate.

**`deployUnifiedDeployer` (lines 74–77):**

> "Deploys the StoxUnifiedDeployer contract via Zoltu for a deterministic address."

One `LibRainDeploy.deployZoltu` call at line 81. Accurate.

**`run()` (lines 86–88):**

> "Entry point for the deployment script. Dispatches to the appropriate deployment function based on the DEPLOYMENT_SUITE environment variable."

Implementation reads `DEPLOYMENT_KEY` and `DEPLOYMENT_SUITE` env vars and dispatches to one of three internal functions or reverts with `UnknownDeploymentSuite`. The `@notice` is accurate as far as it goes but omits the `DEPLOYMENT_KEY` env var entirely.

**`UnknownDeploymentSuite` error (lines 31–33):**

> "Error thrown when the DEPLOYMENT_SUITE env var does not match any known suite."

Accurate — the error is only thrown in `run()`'s else branch (line 100). The `suite` parameter carries the keccak256 hash of the unrecognised string, which aids debugging. No documentation of the parameter is present.

### Typos / stale references / misleading descriptions

No typos found. No stale references. All described contracts, libraries, and constants exist in the codebase and are used as documented.

---

## Findings

### A02-P3-1 — LOW: `run()` does not document the environment variables it requires

**Severity:** LOW

**Location:** `script/Deploy.sol` lines 86–88 (`run()` NatSpec)

**Description:**

`run()` is the public entry point of the deploy script. It reads two environment variables via Forge cheatcodes — `DEPLOYMENT_KEY` (line 90) and `DEPLOYMENT_SUITE` (line 91) — and reverts at the cheatcode level with an opaque error message if either is absent or malformed. The `@notice` comment (lines 86–88) only says the function "dispatches to the appropriate deployment function based on the DEPLOYMENT_SUITE environment variable", omitting `DEPLOYMENT_KEY` entirely and not indicating the accepted values for `DEPLOYMENT_SUITE`.

A maintainer reading only the NatSpec has no way to know which environment variables must be set before invoking the script, or what the valid suite names are. This is especially relevant because the three valid suite strings (`"offchain-asset-receipt-vault-beacon-set"`, `"wrapped-token-vault-beacon-set"`, `"unified-deployer"`) are implicit in the constants but not surfaced in `run()`'s documentation.

**Impact:**

Operational — a misconfigured invocation yields an opaque cheatcode abort rather than `UnknownDeploymentSuite`. The documentation gap increases the chance of operational error during deployment.

**Evidence:**

- Line 90: `uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");` — not mentioned in NatSpec
- Line 91: `bytes32 suite = keccak256(bytes(vm.envString("DEPLOYMENT_SUITE")));` — suite key mentioned without valid values

---

### A02-P3-2 — INFO: `UnknownDeploymentSuite` error missing `@param` for `suite`

**Severity:** INFO

**Location:** `script/Deploy.sol` lines 31–33 (`UnknownDeploymentSuite` error)

**Description:**

The custom error `UnknownDeploymentSuite(bytes32 suite)` has a `@dev` comment describing when it is thrown but does not document the `suite` parameter. The parameter carries the keccak256 hash of the unrecognised `DEPLOYMENT_SUITE` string, which is the primary diagnostic value when debugging a failed deployment. A `@param suite` tag would clarify this.

**Impact:**

INFO only — the error's meaning is inferrable from the `@dev` text and the usage at line 100.
