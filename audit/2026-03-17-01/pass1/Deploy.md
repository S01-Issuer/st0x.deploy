# Pass 1 — Security Audit: `script/Deploy.sol`

**Agent:** A01
**Date:** 2026-03-17
**File:** `script/Deploy.sol` (94 lines)

---

## Evidence of Thorough Reading

### Contract
- `Deploy` (line 32) — inherits `Script` from forge-std

### Functions
| Function | Line | Visibility |
|---|---|---|
| `deployOffchainAssetReceiptVaultBeaconSet(uint256)` | 37 | `internal` |
| `deployWrappedTokenVaultBeaconSet(uint256)` | 55 | `internal` |
| `deployUnifiedDeployer(uint256)` | 69 | `internal` |
| `run()` | 80 | `public` |

### Constants (file-level)
| Constant | Line | Value |
|---|---|---|
| `DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET` | 23-24 | `keccak256("offchain-asset-receipt-vault-beacon-set")` |
| `DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET` | 27 | `keccak256("wrapped-token-vault-beacon-set")` |
| `DEPLOYMENT_SUITE_UNIFIED_DEPLOYER` | 30 | `keccak256("unified-deployer")` |

### Imports (lines 5-19)
- `Script` from `forge-std/Script.sol`
- `OffchainAssetReceiptVaultBeaconSetDeployer`, `OffchainAssetReceiptVaultBeaconSetDeployerConfig` from `ethgild`
- `LibProdDeploy` from `src/lib/LibProdDeploy.sol`
- `StoxReceipt` from `src/concrete/StoxReceipt.sol`
- `StoxReceiptVault` from `src/concrete/StoxReceiptVault.sol`
- `StoxWrappedTokenVaultBeaconSetDeployer`, `StoxWrappedTokenVaultBeaconSetDeployerConfig` from `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol`
- `StoxWrappedTokenVault` from `src/concrete/StoxWrappedTokenVault.sol`
- `StoxUnifiedDeployer` from `src/concrete/deploy/StoxUnifiedDeployer.sol`

### Types/Errors Defined
None defined in this file.

### Referenced External Constants
- `LibProdDeploy.BEACON_INIITAL_OWNER` (hardcoded to `0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b`)

---

## Findings

### A01-1: String revert used instead of custom error

**Severity:** LOW

**Description:**
Line 91 uses a string revert (`revert("Unknown deployment suite")`) instead of a custom error. The project's other contracts consistently define and use custom errors (e.g., `ZeroVaultImplementation()`, `ZeroBeaconOwner()` in `StoxWrappedTokenVaultBeaconSetDeployer.sol`). String reverts consume more gas than custom errors and are inconsistent with the codebase style. While this is a deployment script (not a deployed contract), consistency and adherence to Solidity best practices apply.

**File:** `script/Deploy.sol`, line 91

**Proposed fix:** `.fixes/A01-1.md`

---

### A01-2: Deployed contract addresses are not captured or verified

**Severity:** INFO

**Description:**
All three deployment functions (`deployOffchainAssetReceiptVaultBeaconSet`, `deployWrappedTokenVaultBeaconSet`, `deployUnifiedDeployer`) use bare `new` expressions without capturing the return value. The deployed contract address is never logged, emitted, or stored. While Forge's broadcast mechanism records deployed addresses in its run artifacts, the script itself provides no on-chain or log-level record of what was deployed. This makes post-deployment verification and auditability harder. This is an informational observation about deployment hygiene, not a security vulnerability.

**File:** `script/Deploy.sol`, lines 40-46, 58-63, 72

**No fix file** (INFO severity).

---

### Summary

| ID | Title | Severity |
|---|---|---|
| A01-1 | String revert used instead of custom error | LOW |
| A01-2 | Deployed contract addresses are not captured or verified | INFO |

No CRITICAL, HIGH, or MEDIUM findings. The script is a straightforward Forge deployment script with minimal attack surface. The `run()` function reads environment variables via Forge cheatcodes (`vm.envUint`, `vm.envString`), which are only available in the Forge scripting context and cannot be called on-chain. All deployment functions are `internal`, preventing external invocation. The private key is read from an environment variable (standard Forge practice) and is not hardcoded. The `initialOwner` is sourced from a hardcoded constant in `LibProdDeploy`, which is appropriate for a production deploy script.
