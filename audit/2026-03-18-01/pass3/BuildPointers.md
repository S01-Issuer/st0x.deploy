# Pass 3: Documentation — BuildPointers.sol

## Evidence of Thorough Reading

**Contract name:** `BuildPointers` (inherits `Script`)

**Functions:**

| Line | Name | Visibility | Mutability |
|------|------|------------|------------|
| 17 | `addressConstantString(address addr)` | `internal` | `pure` |
| 28 | `buildContractPointers(string memory name, bytes memory creationCode)` | `internal` | stateful (deploy + file I/O) |
| 47 | `run()` | `external` | stateful (script entrypoint) |

**Types / Errors / Constants defined:** None.

**Imports:**
- `forge-std/Script.sol` — Foundry Script base
- `rain.sol.codegen/lib/LibCodeGen.sol` — `bytesConstantString`
- `rain.sol.codegen/lib/LibFs.sol` — `buildFileForContract`
- `rain.deploy/lib/LibRainDeploy.sol` — `etchZoltuFactory`, `deployZoltu`
- `StoxReceipt`, `StoxReceiptVault`, `StoxWrappedTokenVault`, `StoxUnifiedDeployer`, `StoxWrappedTokenVaultBeacon`, `StoxWrappedTokenVaultBeaconSetDeployer` — for `type(...).creationCode`

---

## Documentation Review

### NatSpec coverage

| Function | NatSpec present | Assessment |
|----------|----------------|------------|
| `addressConstantString` | None | Internal helper; NatSpec optional for scripts |
| `buildContractPointers` | None | Internal helper; NatSpec optional for scripts |
| `run()` | None | External entrypoint; `@notice`/`@dev` recommended |

### Inline comments

One inline comment exists (lines 53–54):

```solidity
// Beacon must be built before the deployer since the deployer imports
// the beacon's pointer file.
```

This comment is **accurate**. `StoxWrappedTokenVaultBeaconSetDeployer` imports `DEPLOYED_ADDRESS as BEACON_ADDRESS` from `../../generated/StoxWrappedTokenVaultBeacon.pointers.sol`, so the beacon pointer file must exist before the deployer's creation bytecode can be captured. The ordering in `run()` correctly enforces this dependency.

### Accuracy of existing documentation

No inaccuracies found. The single inline comment correctly describes the compile-time dependency.

### Typos / stale references / misleading descriptions

None found.

---

## Findings

### A01-P3-3: `run()` external entrypoint has no NatSpec [INFO]

`run()` is the external entry point for the `BuildPointers` Foundry script. It has no `@notice` or `@dev` comment explaining what the script does, what it produces, or any prerequisites (e.g., that it must be run in a context where the source contracts compile, or that it overwrites files in `src/generated/`).

For a build/codegen script whose output files are consumed by production libraries (`LibProdDeployV2`), a brief description of purpose and output location would aid future maintainers who need to know when and how to re-run the script.

The two internal helpers (`addressConstantString`, `buildContractPointers`) perform non-obvious operations (generating inline Solidity source fragments; deploying via the Zoltu factory to capture a deterministic address and runtime bytecode), but as internal functions in a script, their absence of NatSpec is consistent with typical Foundry script practice and is not a finding.

Severity: **INFO** — no correctness impact; documentation-only gap.
