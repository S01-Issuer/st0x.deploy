# Pass 3: Documentation -- BuildPointers.sol

**Auditor:** A01
**Date:** 2026-03-19

## Evidence of Thorough Reading

**File:** `script/BuildPointers.sol` (72 lines)
**Contract name:** `BuildPointers` (inherits `Script` from forge-std, line 21)

**Functions:**

| Line | Name | Visibility | Mutability |
|------|------|------------|------------|
| 22 | `addressConstantString(address addr)` | `internal` | `pure` |
| 33 | `buildContractPointers(string memory name, bytes memory creationCode)` | `internal` | stateful (deploys via Zoltu, writes files via VM) |
| 52 | `run()` | `external` | stateful (script entrypoint) |

**Types / Errors / Constants defined:** None.

**Imports (lines 5-19):**
- `forge-std/Script.sol` (line 5) -- Foundry Script base contract
- `rain.sol.codegen/lib/LibCodeGen.sol` (line 6) -- `bytesConstantString` helper
- `rain.sol.codegen/lib/LibFs.sol` (line 7) -- `buildFileForContract` file writer
- `rain.deploy/lib/LibRainDeploy.sol` (line 8) -- `etchZoltuFactory`, `deployZoltu`
- `StoxReceipt` (line 9)
- `StoxReceiptVault` (line 10)
- `StoxWrappedTokenVault` (line 11)
- `StoxUnifiedDeployer` (line 12)
- `StoxWrappedTokenVaultBeacon` (line 13)
- `StoxWrappedTokenVaultBeaconSetDeployer` (lines 14-16)
- `StoxOffchainAssetReceiptVaultBeaconSetDeployer` (lines 17-19)

---

## Documentation Review

### Contract-level documentation

The `BuildPointers` contract has no NatSpec (`@title`, `@notice`, `@dev`, `@author`) at the contract level. Only an SPDX license header and pragma are present.

### Function-by-function documentation review

#### `addressConstantString` (line 22)

- **NatSpec present:** None.
- **Parameters:** `addr` -- undocumented.
- **Returns:** `string memory` -- undocumented.
- **Assessment:** No NatSpec. This internal helper generates a Solidity constant declaration string for a `DEPLOYED_ADDRESS`. The function name is reasonably descriptive but has no `@notice`, `@dev`, `@param`, or `@return` tags.

#### `buildContractPointers` (line 33)

- **NatSpec present:** None.
- **Parameters:** `name` and `creationCode` -- both undocumented.
- **Returns:** None (void).
- **Assessment:** No NatSpec. This is the core function that deploys a contract via Zoltu and generates the pointer file containing `DEPLOYED_ADDRESS`, `CREATION_CODE`, and `RUNTIME_CODE` constants. Has no `@notice`, `@dev`, or `@param` tags.

#### `run` (line 52)

- **NatSpec present:** None.
- **Parameters:** None.
- **Returns:** None.
- **Assessment:** No NatSpec. This is the Foundry script entrypoint. It etches the Zoltu factory and calls `buildContractPointers` for all 7 contracts in dependency order. Has no `@notice` or `@dev` tags. The inline comments on lines 58-59 and 64 explain the ordering constraints, which is good.

### Inline comments review

- **Line 58-59:** `// Beacon must be built before the deployer since the deployer imports // the beacon's pointer file.` -- Accurate and useful. Explains the ordering dependency between `StoxWrappedTokenVaultBeacon` and `StoxWrappedTokenVaultBeaconSetDeployer`.
- **Line 64:** `// OARV deployer depends on StoxReceipt and StoxReceiptVault pointers.` -- Accurate and useful. Explains the ordering dependency for the OARV deployer.
- The `addressConstantString` function (lines 25-26) embeds NatSpec in the generated output: `/// @dev The deterministic deploy address of the contract when deployed via\n/// the Zoltu factory.\n`. This documentation appears in the generated pointer files, not in `BuildPointers.sol` itself.
- The `buildContractPointers` function (line 43) embeds `/// @dev The creation bytecode of the contract.` and (line 46) `/// @dev The runtime bytecode of the contract.` in generated output via `LibCodeGen.bytesConstantString`. These are accurate.

---

## Findings

### A01-1: Missing NatSpec on contract and all three functions (INFO)

**Severity:** INFO
**File:** `script/BuildPointers.sol`, lines 21, 22, 33, 52

The `BuildPointers` contract and all three of its functions (`addressConstantString`, `buildContractPointers`, `run`) lack NatSpec documentation entirely. While this is an off-chain Foundry script with no on-chain deployment surface, NatSpec would improve maintainability by documenting:
- The contract's purpose (pointer file generation for Zoltu deterministic deployment)
- `addressConstantString`: what it generates and for what purpose
- `buildContractPointers`: the deploy-then-codegen workflow, and the significance of the `name` parameter (must match the contract filename for `LibFs.buildFileForContract`)
- `run`: the full set of contracts processed and why ordering matters

This is INFO severity because the script is well-structured, the inline comments on ordering are good, and the function/parameter names are descriptive enough to understand the code. The absence of NatSpec does not create any risk.

### A01-2: No `@dev` or `@notice` explaining the `name` parameter must match the Solidity filename (LOW)

**Severity:** LOW
**File:** `script/BuildPointers.sol`, line 33

The `name` parameter in `buildContractPointers` is passed directly to `LibFs.buildFileForContract`, which uses it to construct the output file path (e.g., `"StoxReceipt"` becomes `src/generated/StoxReceipt.pointers.sol`). If the `name` does not match the contract's source filename, the generated pointer file will be in the wrong location and will not be importable by the contracts that depend on it. This constraint is non-obvious and undocumented. A `@param` or `@dev` tag should note this requirement.

---

## Summary

The file is a straightforward Foundry build script with good inline ordering comments but no NatSpec documentation. One LOW finding for the undocumented constraint on the `name` parameter. One INFO finding for the overall absence of NatSpec.
