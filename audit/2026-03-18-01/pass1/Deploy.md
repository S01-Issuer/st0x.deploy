# Pass 1: Security — Deploy.sol

**Agent:** A02
**Date:** 2026-03-18
**File:** `script/Deploy.sol` (111 lines)

---

## Evidence of Thorough Reading

### Contract

| Name | Line | Base |
|---|---|---|
| `Deploy` | 37 | `Script` (forge-std) |

### Functions

| Function | Line | Visibility |
|---|---|---|
| `deployOffchainAssetReceiptVaultBeaconSet(uint256 deploymentKey)` | 44 | `internal` |
| `deployWrappedTokenVaultBeaconSet(uint256 deploymentKey)` | 67 | `internal` |
| `deployUnifiedDeployer(uint256 deploymentKey)` | 86 | `internal` |
| `run()` | 97 | `public` |

### Constants (file-level)

| Constant | Line | Value |
|---|---|---|
| `DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET` | 24–25 | `keccak256("offchain-asset-receipt-vault-beacon-set")` |
| `DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET` | 28 | `keccak256("wrapped-token-vault-beacon-set")` |
| `DEPLOYMENT_SUITE_UNIFIED_DEPLOYER` | 31 | `keccak256("unified-deployer")` |

### Errors (file-level)

| Error | Line |
|---|---|
| `UnknownDeploymentSuite(bytes32 suite)` | 35 |

### Imports

| Symbol | Source |
|---|---|
| `Script` | `forge-std/Script.sol` |
| `OffchainAssetReceiptVaultBeaconSetDeployer`, `OffchainAssetReceiptVaultBeaconSetDeployerConfig` | `ethgild/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol` |
| `LibProdDeployV1` | `src/lib/LibProdDeployV1.sol` |
| `StoxReceipt` | `src/concrete/StoxReceipt.sol` |
| `StoxReceiptVault` | `src/concrete/StoxReceiptVault.sol` |
| `StoxWrappedTokenVaultBeaconSetDeployer`, `StoxWrappedTokenVaultBeaconSetDeployerConfig` | `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` |
| `StoxWrappedTokenVault` | `src/concrete/StoxWrappedTokenVault.sol` |
| `StoxUnifiedDeployer` | `src/concrete/deploy/StoxUnifiedDeployer.sol` |
| `LibRainDeploy` | `rain.deploy/lib/LibRainDeploy.sol` |

### External constants referenced

| Constant | Source |
|---|---|
| `LibProdDeployV1.BEACON_INITIAL_OWNER` | `0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b` (rainlang.eth) |

---

## Prior Audit Fix Verification

**A01-1 (string revert → custom error):** Confirmed fixed. `error UnknownDeploymentSuite(bytes32 suite)` is defined at line 35, and `revert UnknownDeploymentSuite(suite)` is used at line 108. No string reverts are present anywhere in the file.

---

## Findings

No findings.

### Security Review Summary

**Input validation:** `run()` reads `DEPLOYMENT_KEY` and `DEPLOYMENT_SUITE` via Forge cheatcodes (`vm.envUint`, `vm.envString`). These cheatcodes abort with a clear error if the variables are absent; no additional validation is needed in the script layer. The suite dispatch uses `keccak256` comparison against three known constants; any unknown value triggers `revert UnknownDeploymentSuite(suite)` with the offending hash for debuggability.

**Access controls:** All three deployment helpers are `internal`, so only `run()` can invoke them. `run()` is `public` but is gated behind Forge's broadcast mechanism — it cannot be meaningfully called on-chain. No `onlyOwner` or similar guard is required for a deploy script.

**Reentrancy:** Not applicable. Each helper opens a broadcast, makes external calls (Zoltu deploy + `new`), and closes the broadcast. There is no state to be reentered and no value handling.

**Arithmetic safety:** No arithmetic operations are present.

**Error handling:** All reverts use custom errors (verified above). There are no unchecked return values in the script logic — `LibRainDeploy.deployZoltu` return values are captured where addresses are needed (`receipt`, `receiptVault`, `wrappedVault`), and the `deployUnifiedDeployer` case deliberately discards the return value (address not needed by the script). This is consistent and correct.

**Assembly blocks:** None present.

**Rounding:** Not applicable.

**Private key handling:** The deployer private key is read from the environment (`vm.envUint("DEPLOYMENT_KEY")`) and passed directly to `vm.startBroadcast`. It is never stored, logged, or emitted. This is standard Forge practice.

**Hardcoded owner:** `LibProdDeployV1.BEACON_INITIAL_OWNER` is a constant resolving to `rainlang.eth` (`0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b`), which is appropriate and intentional for a production deploy script.

**Version import:** The script correctly imports `LibProdDeployV1` (the current versioned constants library), consistent with the versioning guidance in `CLAUDE.md`.
