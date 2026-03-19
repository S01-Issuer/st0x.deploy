# Pass 2: Test Coverage -- BuildPointers.sol

**Auditor:** A01
**Date:** 2026-03-19

## Evidence of Thorough Reading

**File:** `script/BuildPointers.sol` (72 lines)
**Contract name:** `BuildPointers` (inherits `Script` from forge-std)

**Functions:**

| Line | Name | Visibility | Mutability |
|------|------|------------|------------|
| 22 | `addressConstantString(address addr)` | `internal` | `pure` |
| 33 | `buildContractPointers(string memory name, bytes memory creationCode)` | `internal` | stateful (deploys + writes files via VM) |
| 52 | `run()` | `external` | stateful (script entrypoint) |

**Types / Errors / Constants defined:** None.

**Imports (lines 5-19):**
- `forge-std/Script.sol` -- Foundry Script base
- `rain.sol.codegen/lib/LibCodeGen.sol` -- `bytesConstantString`
- `rain.sol.codegen/lib/LibFs.sol` -- `buildFileForContract`
- `rain.deploy/lib/LibRainDeploy.sol` -- `etchZoltuFactory`, `deployZoltu`
- 7 Stox contracts for `type(...).creationCode`: `StoxReceipt`, `StoxReceiptVault`, `StoxWrappedTokenVault`, `StoxUnifiedDeployer`, `StoxWrappedTokenVaultBeacon`, `StoxWrappedTokenVaultBeaconSetDeployer`, `StoxOffchainAssetReceiptVaultBeaconSetDeployer`

---

## Coverage Analysis

### Direct test coverage

Grep for `BuildPointers`, `buildContractPointers`, and `addressConstantString` across `test/`: **zero results**. No test file directly invokes or references this script.

### Indirect test coverage

The script's sole purpose is generating `src/generated/*.pointers.sol` files containing `DEPLOYED_ADDRESS`, `CREATION_CODE`, and `RUNTIME_CODE` constants. These outputs are extensively validated by downstream tests:

**`test/src/lib/LibProdDeployV2.t.sol`** (306 lines, 28 test functions) validates all 7 generated pointer files:
- Zoltu deploy address matches `LibProdDeployV2` constant (7 tests)
- Fresh-compiled codehash matches `LibProdDeployV2` codehash constant (7 tests)
- Pointer `CREATION_CODE` matches `type(...).creationCode` (7 tests)
- Pointer `RUNTIME_CODE` matches deployed bytecode (7 tests)
- Pointer `DEPLOYED_ADDRESS` matches `LibProdDeployV2` address constant (7 tests -- covering address consistency between pointer files and the prod deploy library)

**`test/src/concrete/deploy/StoxProdV2.t.sol`** (84 lines, 5 fork tests) validates all V2 contracts are deployed on-chain with correct codehashes across Arbitrum, Base, Base Sepolia, Flare, and Polygon.

### Function-by-function assessment

| Function | Direct coverage | Indirect coverage | Notes |
|----------|----------------|-------------------|-------|
| `addressConstantString` | None | Full | Output validated via `testGeneratedAddress*` tests in `LibProdDeployV2.t.sol` |
| `buildContractPointers` | None | Full | All three generated constants (`DEPLOYED_ADDRESS`, `CREATION_CODE`, `RUNTIME_CODE`) validated per contract |
| `run()` | None | Full | All 7 contracts' pointer files validated downstream |

### Assessment

`BuildPointers.sol` is a Foundry codegen script that runs in the VM to produce `.pointers.sol` files. It is not deployed on-chain and has no attack surface. Direct unit testing of Foundry scripts that use `vm.writeFile` and `vm.etch` is impractical and not standard practice.

The indirect validation through `LibProdDeployV2.t.sol` is thorough: it verifies every constant the script produces (addresses, creation code, runtime code, codehashes) against fresh compiler output and Zoltu-deployed instances. The fork tests in `StoxProdV2.t.sol` further confirm these values match live on-chain state.

---

## Findings

No findings. The absence of direct unit tests for `BuildPointers.sol` is expected and appropriate for a Foundry build script. The script's correctness is comprehensively validated through indirect tests that verify every generated constant against compiler output, local Zoltu deployments, and live on-chain state across multiple networks.
