# Pass 4: Code Quality — 2026-03-19-01

## Files Reviewed

All 11 source files, 2 test helper contracts, 2 test libraries, and 14 test files were read in full.

## Build Check

`nix develop -c forge build` — **clean**, no warnings.

## Evidence of Reading

### Source files

- **A01** `script/BuildPointers.sol` (72 lines): Contract `BuildPointers` (L21). Functions: `addressConstantString` (L22), `buildContractPointers` (L33), `run` (L52). No types/errors/constants.
- **A02** `script/Deploy.sol` (153 lines): Contract `Deploy` (L37). Functions: `deploySuite` (L40), `run` (L82). Error: `UnknownDeploymentSuite` (L23). 7 file-level constants (L27-35). State: `depCodeHashes` mapping (L38).
- **A03** `src/concrete/StoxReceipt.sol` (12 lines): Contract `StoxReceipt` (L12). Empty body.
- **A04** `src/concrete/StoxReceiptVault.sol` (11 lines): Contract `StoxReceiptVault` (L11). Empty body.
- **A05** `src/concrete/StoxWrappedTokenVault.sol` (71 lines): Contract `StoxWrappedTokenVault` (L29). Functions: `constructor` (L36), `initialize(address)` (L43), `initialize(bytes)` (L51), `name` (L63), `symbol` (L68). Error: `ZeroAsset` (L13). Event: `StoxWrappedTokenVaultInitialized` (L33).
- **A06** `src/concrete/StoxWrappedTokenVaultBeacon.sol` (13 lines): Contract `StoxWrappedTokenVaultBeacon` (L11). Empty body.
- **A07** `src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol` (21 lines): Contract `StoxOffchainAssetReceiptVaultBeaconSetDeployer` (L15). Empty body.
- **A08** `src/concrete/deploy/StoxUnifiedDeployer.sol` (45 lines): Contract `StoxUnifiedDeployer` (L19). Function: `newTokenAndWrapperVault` (L35). Event: `Deployment` (L25).
- **A09** `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` (55 lines): Contract `StoxWrappedTokenVaultBeaconSetDeployer` (L25). Function: `newStoxWrappedTokenVault` (L39). Event: `Deployment` (L30). Errors: `InitializeVaultFailed` (L11), `ZeroVaultAsset` (L14).
- **A10** `src/lib/LibProdDeployV1.sol` (106 lines): Library `LibProdDeployV1` (L10). 19 constants, 0 functions.
- **A11** `src/lib/LibProdDeployV2.sol` (81 lines): Library `LibProdDeployV2` (L38). 15 constants, 0 functions.

### Test utilities

- `test/concrete/MockERC20.sol` (14 lines): Contract `MockERC20` (L8). Functions: `constructor` (L9), `mint` (L11).
- `test/concrete/BadInitializeVault.sol` (11 lines): Contract `BadInitializeVault` (L7). Function: `initialize` (L8).
- `test/lib/LibTestDeploy.sol` (66 lines): Library `LibTestDeploy` (L24). Functions: `deployWrappedTokenVaultBeaconSet` (L25), `deployOffchainAssetReceiptVaultBeaconSet` (L43), `deployAll` (L59).
- `test/lib/LibTestProd.sol` (13 lines): Library `LibTestProd` (L9). Function: `createSelectForkBase` (L10). Constant: `PROD_TEST_BLOCK_NUMBER_BASE` (L7).

### Test files

All 14 test files read in full. Contracts: `DeployTest`, `StoxReceiptTest`, `StoxReceiptVaultTest`, `StoxWrappedTokenVaultTest`, `StoxWrappedTokenVaultV1ProdBaseTest`, `StoxWrappedTokenVaultV2Test`, `StoxWrappedTokenVaultBeaconTest`, `StoxProdV2Test`, `StoxUnifiedDeployerTest`, `StoxUnifiedDeployerIntegrationTest`, `StoxProdBaseTest`, `StoxWrappedTokenVaultBeaconSetDeployerTest`, `LibProdDeployV1Test`, `LibProdDeployV1V2Test`, `LibProdDeployV2Test`.

## Findings

### A05-P4-1 — LOW — `_`-prefixed helper functions in test files

CLAUDE.md states: "No meaningless `_`-prefixed helpers. All function names must be descriptive and convey what the function does. This applies to all files including tests."

4 functions across 3 test files use `_`-prefixed names:
- `test/src/concrete/StoxWrappedTokenVaultV1.prod.base.t.sol:16` — `_v1Beacon()`
- `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol:26` — `_checkAllOnChain()`
- `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol:116` — `_checkUnchangedCreationBytecodes()`
- `test/src/concrete/deploy/StoxProdV2.t.sol:14` — `_checkAllV2OnChain()`

### A05-P4-2 — LOW — MockERC20.sol uses `^0.8.25` pragma

`test/concrete/MockERC20.sol` uses `pragma solidity ^0.8.25` but it is a contract, not a library. Per CLAUDE.md compiler settings convention: exact pin `=0.8.25` in contracts, `^0.8.25` in libraries.

### A10-P4-1 — LOW — slither-disable annotation lacks explanatory comment

`src/lib/LibProdDeployV1.sol:9` has `// slither-disable-next-line too-many-digits` without an accompanying comment explaining why the suppression is needed. Global CLAUDE.md requires: "Always add a comment explaining why when adding `slither-disable` annotations."

(Also reported in Pass 1 A10-1 and Pass 3 A10-P3-1 — consolidated here for completeness.)

## Non-findings

- **No bare `src/` import paths** in any project file (src/, test/, script/). All imports use relative paths or remappings.
- **No commented-out code** found anywhere.
- **No build warnings** — `forge build` completes clean.
- **No leaky abstractions** — LibProdDeployV2 correctly mediates between generated pointer files and consuming contracts.
- **No test utility duplication** — all test files consistently use `LibTestDeploy` and `LibTestProd` helpers.
- **Consistent style** across files: license headers, import formatting, NatSpec patterns.
- **Dependency versions**: All first-party files use consistent Solidity pragma per convention (except MockERC20 noted above).
