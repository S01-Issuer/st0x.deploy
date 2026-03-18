# Pass 2: Test Coverage — BuildPointers.sol

## Evidence of Thorough Reading

**Contract name:** `BuildPointers` (inherits `Script`)

**Functions:**

| Line | Name | Visibility | Mutability |
|------|------|------------|------------|
| 15 | `addressConstantString(address addr)` | `internal` | `pure` |
| 26 | `buildContractPointers(string memory name, bytes memory creationCode)` | `internal` | stateful (calls deploy + file I/O) |
| 45 | `run()` | `external` | stateful (script entrypoint) |

**Types / Errors / Constants defined:** None in this file.

**Imports:**
- `forge-std/Script.sol` — Foundry Script base
- `rain.sol.codegen/lib/LibCodeGen.sol` — `bytesConstantString`
- `rain.sol.codegen/lib/LibFs.sol` — `buildFileForContract`
- `rain.deploy/lib/LibRainDeploy.sol` — `etchZoltuFactory`, `deployZoltu`
- `StoxReceipt`, `StoxReceiptVault`, `StoxWrappedTokenVault`, `StoxUnifiedDeployer` — for `type(...).creationCode`

---

## Coverage Analysis

### Search results

Grep for "BuildPointers" across `test/`: **no results**.
No `test/script/BuildPointers.t.sol` or equivalent file exists.

The only test file under `test/script/` is `Deploy.t.sol`, which covers the `Deploy.sol` script, not `BuildPointers.sol`.

### Function-by-function assessment

| Function | Test coverage | Notes |
|----------|--------------|-------|
| `addressConstantString` | None | No test exercises the output format |
| `buildContractPointers` | None | No test exercises deploy + file generation |
| `run()` | None | No test invokes the script entrypoint |

### Assessment — build script vs deployed contract

`BuildPointers.sol` is a Foundry build/codegen script. Its output is the `src/generated/*.pointers.sol` files, which are in turn consumed by `LibProdDeployV2` (and future versioned libs). The fork tests in `test/src/lib/LibProdDeployV2.t.sol` indirectly validate the *output* of a prior run of the script (codehash constants), but they do not invoke the script itself.

Typical practice for Foundry build scripts is that they are not unit-tested directly (Foundry's `vm.etch`, `vm.writeFile` etc. are difficult to assert on in a test context). However, the **correct generation of pointer files** is a load-bearing property of the system — if the script produces wrong constants, production deployments will use wrong bytecode. This makes indirect validation through fork tests, which is the current approach, the most practical form of coverage.

The absence of direct test coverage for `run()` is therefore expected and acceptable for a build script, provided the generated output is validated downstream (which it is, via `LibProdDeployV2.t.sol` codehash assertions).

---

## Findings

No findings. The absence of direct unit tests for `BuildPointers.sol` is consistent with standard Foundry build-script practice. The script's correctness is validated indirectly through fork tests that assert the codehash constants produced by the script match live Base mainnet deployments. This provides sufficient confidence in the script's output for a codegen tool of this scope.
