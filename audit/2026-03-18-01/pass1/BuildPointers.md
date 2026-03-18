# Pass 1: Security — BuildPointers.sol

## Evidence of Thorough Reading

**Contract name:** `BuildPointers` (inherits `Script`)

**Functions:**

| Line | Name | Visibility | Mutability |
|------|------|------------|------------|
| 15 | `addressConstantString(address addr)` | `internal` | `pure` |
| 26 | `buildContractPointers(string memory name, bytes memory creationCode)` | `internal` | (stateful — calls deploy) |
| 45 | `run()` | `external` | (entrypoint) |

**Types / Errors / Constants defined:** None in this file.

**Imports:**
- `forge-std/Script.sol` — Foundry Script base
- `rain.sol.codegen/lib/LibCodeGen.sol` — code generation helpers
- `rain.sol.codegen/lib/LibFs.sol` — file writing helpers
- `rain.deploy/lib/LibRainDeploy.sol` — `etchZoltuFactory`, `deployZoltu`
- `StoxReceipt`, `StoxReceiptVault`, `StoxWrappedTokenVault`, `StoxUnifiedDeployer` — for `type(...).creationCode`

**Execution flow of `run()`:**
1. `LibRainDeploy.etchZoltuFactory(vm)` — etches Zoltu bytecode into the factory address via `vm.etch`.
2. Four calls to `buildContractPointers`, each passing a string name and the compile-time `type(X).creationCode`.

**Execution flow of `buildContractPointers(name, creationCode)`:**
1. `LibRainDeploy.deployZoltu(creationCode)` — low-level `call` to the etched Zoltu factory; returns the deployed address.  Reverts (custom error `DeployFailed`) on failure.
2. `LibFs.buildFileForContract(vm, deployed, name, body)` — computes output path `src/generated/<name>.pointers.sol`, removes it if it exists, writes the new file.
3. Body is built from `addressConstantString(deployed)`, `LibCodeGen.bytesConstantString` for `CREATION_CODE`, and `LibCodeGen.bytesConstantString` for `RUNTIME_CODE` (`deployed.code`).

---

## Findings

### A01-1: `buildContractPointers` reads `deployed.code` after `deployZoltu` but before confirming the pointer file was written [INFO]

`buildContractPointers` (line 39) captures `deployed.code` inline inside the `string.concat` call that is passed to `LibFs.buildFileForContract`. If `LibFs.buildFileForContract` later reverts (e.g., filesystem error), no pointer file is written, but the etched contract remains in the in-memory Foundry VM state. On a second invocation the Zoltu factory would return the same address (deterministic CREATE), `deployZoltu` would see `deployedAddress.code.length != 0` and revert with `DeployFailed` because `success` would be false (CREATE at an occupied address returns false/zero-address). This is a Foundry script-only scenario with no on-chain assets at risk; the user simply re-runs the script. The ordering of operations is therefore acceptable for a build script, but the silent dependency on the factory address being empty deserves a note.

Severity: INFO — no assets at risk; this is a build/codegen script only.

No findings of LOW or higher severity.
