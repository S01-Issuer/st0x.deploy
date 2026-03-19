# Pass 1: Security -- BuildPointers.sol

## Evidence of Thorough Reading

**File:** `script/BuildPointers.sol` (72 lines)

**Contract name:** `BuildPointers` (inherits `Script` from forge-std)

**Functions:**

| Line | Name | Visibility | Mutability |
|------|------|------------|------------|
| 22 | `addressConstantString(address addr)` | `internal` | `pure` |
| 33 | `buildContractPointers(string memory name, bytes memory creationCode)` | `internal` | stateful (deploys + writes files) |
| 52 | `run()` | `external` | stateful (entrypoint) |

**Types / Errors / Constants defined:** None.

**Imports:**
- `forge-std/Script.sol` (line 5) -- Foundry Script base
- `rain.sol.codegen/lib/LibCodeGen.sol` (line 6) -- code generation helpers
- `rain.sol.codegen/lib/LibFs.sol` (line 7) -- filesystem helpers
- `rain.deploy/lib/LibRainDeploy.sol` (line 8) -- `etchZoltuFactory`, `deployZoltu`
- `StoxReceipt` (line 9)
- `StoxReceiptVault` (line 10)
- `StoxWrappedTokenVault` (line 11)
- `StoxUnifiedDeployer` (line 12)
- `StoxWrappedTokenVaultBeacon` (line 13)
- `StoxWrappedTokenVaultBeaconSetDeployer` (lines 14-16)
- `StoxOffchainAssetReceiptVaultBeaconSetDeployer` (lines 17-19)

**Execution flow of `run()` (line 52):**
1. Etches Zoltu factory bytecode at the factory address via `LibRainDeploy.etchZoltuFactory(vm)` (line 53).
2. Calls `buildContractPointers` seven times in dependency order (lines 55-69):
   - StoxReceipt
   - StoxReceiptVault
   - StoxWrappedTokenVault
   - StoxWrappedTokenVaultBeacon (comment on line 58-59 explains ordering)
   - StoxWrappedTokenVaultBeaconSetDeployer
   - StoxOffchainAssetReceiptVaultBeaconSetDeployer (comment on line 64)
   - StoxUnifiedDeployer

**Execution flow of `buildContractPointers(name, creationCode)` (line 33):**
1. Deploys creation code via Zoltu factory (`LibRainDeploy.deployZoltu`) and captures the deployed address (line 34).
2. Calls `LibFs.buildFileForContract` to write a `.pointers.sol` file containing:
   - `DEPLOYED_ADDRESS` constant (via `addressConstantString`)
   - `CREATION_CODE` constant (via `LibCodeGen.bytesConstantString`)
   - `RUNTIME_CODE` constant from `deployed.code` (via `LibCodeGen.bytesConstantString`)

---

## Findings

No findings of LOW or higher severity.

This file is a Foundry build script (`forge script`) that runs exclusively off-chain in the Foundry VM to generate pointer files. It has no on-chain deployment surface, no access control requirements, no external calls beyond the etched Zoltu factory, and no user-supplied inputs. The `deployZoltu` function in `LibRainDeploy` correctly validates deployment success, non-zero address, and non-empty code before returning. The build ordering documented in comments (lines 58-59, 64) correctly reflects the compile-time dependency chain -- the beacon pointer file must exist before the deployer that imports it can compile, and the OARV deployer depends on StoxReceipt and StoxReceiptVault pointers.

No security vulnerabilities, input validation gaps, arithmetic issues, access control problems, or reentrancy risks are present. The script operates entirely within the Foundry VM sandbox and produces deterministic output files.
