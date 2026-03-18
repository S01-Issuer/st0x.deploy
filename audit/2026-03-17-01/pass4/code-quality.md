# Pass 4: Code Quality — All Source Files

## Evidence of Thorough Reading

All 10 project-owned `.sol` files read in full:

| ID | File | Lines | Key elements verified |
|---|---|---|---|
| A01 | `script/Deploy.sol` | 94 | 3 file-level constants, 3 internal deploy fns, `run()` dispatcher, 8 imports |
| A02 | `src/concrete/StoxReceipt.sol` | 11 | Empty body inheriting `Receipt`, 1 import |
| A03 | `src/concrete/StoxReceiptVault.sol` | 12 | Empty body inheriting `OffchainAssetReceiptVault`, 1 import |
| A04 | `src/concrete/StoxWrappedTokenVault.sol` | 63 | ERC4626 + ICloneableV2, constructor, 2 `initialize` overloads, `name()`/`symbol()` overrides, 1 event, 4 imports |
| A05 | `src/concrete/deploy/StoxUnifiedDeployer.sol` | 41 | 1 external fn, 1 event, 4 imports (mixed relative/bare) |
| A06 | `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` | 87 | 4 custom errors, 1 struct, constructor, 1 external fn, 1 event, 1 immutable, 5 imports |
| A07 | `src/lib/LibProdDeploy.sol` | 24 | Constants-only library, 6 constants, 0 imports |
| T01 | `test/src/concrete/deploy/StoxUnifiedDeployer.t.sol` | 50 | 1 fuzz test with vm.etch/vm.mockCall, 5 imports |
| T02 | `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` | 24 | Codehash + fork verification, 4 imports |
| T03 | `test/lib/LibTestProd.sol` | 13 | Fork helper library, 1 constant, 1 function |

No files exist under `test/util/`.

Build check: `forge build` completed successfully with Solc 0.8.25 — no warnings.

---

## Finding P4-1: Bare `src/` import paths break submodule usage [LOW]

**Affected files and lines:**

| File | Lines | Imports using bare `src/` |
|---|---|---|
| `script/Deploy.sol` | 11-19 | `src/lib/LibProdDeploy.sol`, `src/concrete/StoxReceipt.sol`, `src/concrete/StoxReceiptVault.sol`, `src/concrete/StoxWrappedTokenVault.sol`, `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol`, `src/concrete/deploy/StoxUnifiedDeployer.sol` |
| `src/concrete/deploy/StoxUnifiedDeployer.sol` | 10, 12 | `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol`, `src/concrete/StoxWrappedTokenVault.sol` |
| `test/src/concrete/deploy/StoxUnifiedDeployer.t.sol` | 11-14 | `src/concrete/deploy/StoxUnifiedDeployer.sol`, `src/lib/LibProdDeploy.sol`, `src/concrete/StoxWrappedTokenVault.sol`, `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` |
| `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` | 7, 9 | `src/concrete/deploy/StoxUnifiedDeployer.sol`, `src/lib/LibProdDeploy.sol` |

Bare `src/` paths rely on Foundry's auto-remapping of the project root. If this repository is consumed as a git submodule or library, the `src/` prefix resolves relative to the *consumer's* project root, not this repo. The two source files that already use relative imports (`StoxUnifiedDeployer.sol` line 11: `../../lib/LibProdDeploy.sol`; `StoxWrappedTokenVaultBeaconSetDeployer.sol` line 8: `../StoxWrappedTokenVault.sol`) prove the correct pattern is available.

**Recommendation:** Replace all `src/` imports in source files with relative paths. For test/script files, either use relative paths or define a remapping (e.g., `st0x.deploy/=src/`).

---

## Finding P4-2: Mixed import path styles within single file (StoxUnifiedDeployer.sol) [LOW]

**File:** `src/concrete/deploy/StoxUnifiedDeployer.sol`

Lines 10-12 mix three different import path conventions in one file:

```
import {StoxWrappedTokenVaultBeaconSetDeployer} from "src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";  // bare src/
import {LibProdDeploy} from "../../lib/LibProdDeploy.sol";  // relative
import {StoxWrappedTokenVault} from "src/concrete/StoxWrappedTokenVault.sol";  // bare src/
```

This is the only source file that mixes relative and bare `src/` paths. All other source files are internally consistent (either all relative like `StoxWrappedTokenVaultBeaconSetDeployer.sol`, or all bare `src/` like `Deploy.sol`).

**Recommendation:** Normalize to relative paths: `./StoxWrappedTokenVaultBeaconSetDeployer.sol` and `../StoxWrappedTokenVault.sol`.

---

## Finding P4-3: Bare `lib/` import path in test file [LOW]

**File:** `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol`, line 8

```
import {LibExtrospectBytecode} from "lib/rain.extrospection/src/lib/LibExtrospectBytecode.sol";
```

This is the only import across all project-owned files that uses a bare `lib/` path to reference a dependency. The `ethgild` and `rain.factory` dependencies are accessed via remappings defined in `foundry.toml`. The `rain.extrospection` dependency has no remapping, so the test reaches directly into `lib/` by absolute submodule path.

**Recommendation:** Add a remapping for `rain.extrospection` in `foundry.toml` (e.g., `rain.extrospection/=lib/rain.extrospection/src/`), then import as `rain.extrospection/lib/LibExtrospectBytecode.sol`. Alternatively, remove the import entirely -- see P4-4.

---

## Finding P4-4: Unused import of LibExtrospectBytecode [LOW]

**File:** `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol`, line 8

```
import {LibExtrospectBytecode} from "lib/rain.extrospection/src/lib/LibExtrospectBytecode.sol";
```

`LibExtrospectBytecode` is imported but never referenced in the test file. The test uses only `StoxUnifiedDeployer`, `LibProdDeploy`, and `LibTestProd`. This import was likely left over from an earlier version of the test that trimmed CBOR metadata before codehash comparison.

**Recommendation:** Remove the unused import.

---

## Finding P4-5: Bare `test/` import path in test file [INFO]

**File:** `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol`, line 10

```
import {LibTestProd} from "test/lib/LibTestProd.sol";
```

Uses a bare `test/` path. Same submodule-breakage concern as bare `src/` paths, though less impactful since test files are not consumed as libraries. Noted for consistency.

---

## Finding P4-6: Unused constant `STOX_WRAPPED_TOKEN_VAULT` in LibProdDeploy [LOW]

**File:** `src/lib/LibProdDeploy.sol`, line 17

```
address constant STOX_WRAPPED_TOKEN_VAULT = address(0x80A79767F2d7c24A0577f791eC2Af74a7c9A1eD1);
```

This constant is defined but never referenced anywhere in the project (source, tests, or scripts). All other constants in `LibProdDeploy` have at least one consumer. Dead code in a production address registry is a maintenance risk -- it may become stale without anyone noticing.

**Recommendation:** Remove the constant, or add a codehash verification test (similar to `STOX_UNIFIED_DEPLOYER`) if it is intended for future use.

---

## Finding P4-7: Deployment event `indexed` inconsistency across contracts [INFO]

**Affected files:**
- `src/concrete/deploy/StoxUnifiedDeployer.sol` line 25: `event Deployment(address sender, address asset, address wrapper)` -- no `indexed`
- `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` line 49: `event Deployment(address sender, address stoxWrappedTokenVault)` -- no `indexed`
- `src/concrete/StoxWrappedTokenVault.sol` line 29: `event StoxWrappedTokenVaultInitialized(address indexed sender, address indexed asset)` -- both `indexed`

The two deployer contracts and the upstream ethgild deployer all omit `indexed` on their `Deployment` events, so the deployer convention is internally consistent. However, `StoxWrappedTokenVault` uses `indexed` on both parameters of its event. This creates an inconsistency within the project: deployer events cannot be efficiently filtered by sender/address, while the vault's initialization event can.

Already noted in pass 1 (A05-2) as a deliberate codebase choice for deployers. Flagged here only for the cross-contract inconsistency with `StoxWrappedTokenVaultInitialized`.

---

## Finding P4-8: Pragma inconsistency between libraries and concrete contracts [INFO]

**Already flagged:** A07-2 in prior passes.

For completeness: `LibProdDeploy.sol` and `LibTestProd.sol` use `^0.8.25` while all other files use `=0.8.25`. The `^` pragma in a library is defensible (wider compatibility for consumers), but within a single-version project compiled with `solc = "0.8.25"` in `foundry.toml`, the difference is cosmetic.

---

## Finding P4-9: No `openzeppelin-contracts` remapping in foundry.toml [INFO]

**File:** `foundry.toml`

The remappings section defines paths for `ethgild/`, `rain.factory/`, and `openzeppelin-contracts-upgradeable/`, but not for `openzeppelin-contracts/`. The latter resolves via Foundry's auto-discovery of `lib/` subdirectories (through the ethgild submodule). This works but is implicit -- if the dependency tree changes or if a second `openzeppelin-contracts` directory appears at a different path, resolution becomes ambiguous.

`StoxWrappedTokenVault.sol` and `StoxWrappedTokenVaultBeaconSetDeployer.sol` both import from `openzeppelin-contracts/` and depend on this auto-resolution.

---

## Summary

| ID | Title | Severity | File(s) |
|---|---|---|---|
| P4-1 | Bare `src/` import paths break submodule usage | LOW | Deploy.sol, StoxUnifiedDeployer.sol, tests |
| P4-2 | Mixed import path styles within single file | LOW | StoxUnifiedDeployer.sol |
| P4-3 | Bare `lib/` import path in test file | LOW | StoxUnifiedDeployer.prod.base.t.sol |
| P4-4 | Unused import of LibExtrospectBytecode | LOW | StoxUnifiedDeployer.prod.base.t.sol |
| P4-5 | Bare `test/` import path in test file | INFO | StoxUnifiedDeployer.prod.base.t.sol |
| P4-6 | Unused constant `STOX_WRAPPED_TOKEN_VAULT` | LOW | LibProdDeploy.sol |
| P4-7 | Deployment event `indexed` inconsistency | INFO | StoxUnifiedDeployer.sol, StoxWrappedTokenVaultBeaconSetDeployer.sol, StoxWrappedTokenVault.sol |
| P4-8 | Pragma inconsistency (known) | INFO | LibProdDeploy.sol, LibTestProd.sol |
| P4-9 | No `openzeppelin-contracts` remapping | INFO | foundry.toml |

**Build warnings:** None. `forge build` completed cleanly with Solc 0.8.25.

**Not re-flagged (known items):**
- BEACON_INIITAL_OWNER typo (A07-1)
- Pragma inconsistency ^0.8.25 vs =0.8.25 (A07-2) -- mentioned in P4-8 for context only
- String revert in Deploy.sol (A01-1)
- Duplicate errors with ethgild (A06-1)
