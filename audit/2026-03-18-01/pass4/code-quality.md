# Pass 4: Code Quality — st0x.deploy

**Date:** 2026-03-18
**Auditor:** Claude Sonnet 4.6

---

## Evidence of Thorough Reading

### A01 — script/BuildPointers.sol (59 lines)

**Contract:** `BuildPointers is Script` — line 16

**Functions:**
- `addressConstantString(address addr) internal pure returns (string memory)` — line 17
- `buildContractPointers(string memory name, bytes memory creationCode) internal` — line 28
- `run() external` — line 47

**Imports:** `Script`, `LibCodeGen`, `LibFs`, `LibRainDeploy`, `StoxReceipt`, `StoxReceiptVault`, `StoxWrappedTokenVault`, `StoxUnifiedDeployer`, `StoxWrappedTokenVaultBeacon`, `StoxWrappedTokenVaultBeaconSetDeployer`

---

### A02 — script/Deploy.sol (112 lines)

**File-level symbols:**
- `error UnknownDeploymentSuite(bytes32 suite)` — line 18
- `bytes32 constant DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET` — line 21
- `bytes32 constant DEPLOYMENT_SUITE_UNIFIED_DEPLOYER` — line 24

**Contract:** `Deploy is Script` — line 26

**State variables:**
- `mapping(string => mapping(address => bytes32)) internal depCodeHashes` — line 27

**Functions:**
- `deployWrappedTokenVaultBeaconSet() internal` — line 31
- `deployUnifiedDeployer() internal` — line 82
- `run() public` — line 101

**Note:** `DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET` does NOT exist in this file. See finding A02-P4-1.

---

### A03 — src/concrete/StoxReceipt.sol (10 lines)

**Contract:** `StoxReceipt is Receipt` — line 10 (no functions beyond inherited)

---

### A04 — src/concrete/StoxReceiptVault.sol (11 lines)

**Contract:** `StoxReceiptVault is OffchainAssetReceiptVault` — line 11 (no functions beyond inherited)

---

### A05 — src/concrete/StoxWrappedTokenVault.sol (69 lines)

**File-level symbols:**
- `error ZeroAsset()` — line 12

**Contract:** `StoxWrappedTokenVault is ERC4626Upgradeable, ICloneableV2` — line 28

**Events:**
- `StoxWrappedTokenVaultInitialized(address indexed sender, address indexed asset)` — line 32

**Functions:**
- `constructor()` — line 34 (calls `_disableInitializers()`)
- `initialize(address asset) external pure returns (bytes32)` — line 41 (always reverts)
- `initialize(bytes calldata data) external initializer returns (bytes32)` — line 49
- `name() public view override(IERC20Metadata, ERC20Upgradeable) returns (string memory)` — line 61
- `symbol() public view override(IERC20Metadata, ERC20Upgradeable) returns (string memory)` — line 66

---

### A06 — src/concrete/deploy/StoxUnifiedDeployer.sol (45 lines)

**Contract:** `StoxUnifiedDeployer` — line 19

**Events:**
- `Deployment(address sender, address asset, address wrapper)` — line 25

**Functions:**
- `newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config) external` — line 35

---

### A07 — src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol (56 lines)

**File-level symbols:**
- `error InitializeVaultFailed()` — line 12
- `error ZeroVaultAsset()` — line 15

**Contract:** `StoxWrappedTokenVaultBeaconSetDeployer` — line 26

**Events:**
- `Deployment(address sender, address stoxWrappedTokenVault)` — line 31

**Functions:**
- `newStoxWrappedTokenVault(address asset) external returns (StoxWrappedTokenVault)` — line 40

**Imports:**
- `IBeacon` — line 5 (imported but not used; leftover from V1 version)

---

### A08 — src/lib/LibProdDeployV1.sol (99 lines; large due to embedded bytecodes)

**Library:** `LibProdDeployV1` — line 10

**Address constants:**
- `BEACON_INITIAL_OWNER` — line 14
- `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` — line 18
- `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` — line 23
- `STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION` — line 30
- `STOX_UNIFIED_DEPLOYER` — line 39
- `STOX_RECEIPT_IMPLEMENTATION` — line 44
- `STOX_RECEIPT_VAULT_IMPLEMENTATION` — line 57

**Codehash constants:**
- `PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` — line 34
- `PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1` — line 47
- `PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` — line 60
- `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` — line 70
- `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` — line 83
- `PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1` — line 96

**Bytecode constants:** (several large `bytes constant PROD_*_CREATION_BYTECODE_V1` entries)

**Imports:** none (no imports; all values are hardcoded literals or inline)

---

### A09 — src/lib/LibProdDeployV2.sol (65 lines)

**Library:** `LibProdDeployV2` — line 34

**Constants (all sourced from generated pointers):**
- `STOX_RECEIPT` / `STOX_RECEIPT_CODEHASH` — lines 36–38
- `STOX_RECEIPT_VAULT` / `STOX_RECEIPT_VAULT_CODEHASH` — lines 41–43
- `STOX_WRAPPED_TOKEN_VAULT` / `STOX_WRAPPED_TOKEN_VAULT_CODEHASH` — lines 46–48
- `STOX_UNIFIED_DEPLOYER` / `STOX_UNIFIED_DEPLOYER_CODEHASH` — lines 51–53
- `STOX_WRAPPED_TOKEN_VAULT_BEACON` / `STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH` — lines 56–58
- `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` / `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH` — lines 61–64

---

### Test files

**test/lib/LibTestProd.sol** (13 lines)
- `uint256 constant PROD_TEST_BLOCK_NUMBER_BASE = 43482822` — line 7
- `library LibTestProd` — line 9
- `createSelectForkBase(Vm vm) internal` — line 10

**test/script/Deploy.t.sol** (35 lines)
- `contract DeployTest is Test` — line 14
- `testDeploymentSuiteConstants() external pure` — line 16
- `testUnknownDeploymentSuiteReverts() external` — line 26

**test/concrete/MockERC20.sol** (14 lines)
- `contract MockERC20 is ERC20` — line 8
- `constructor()` — line 9
- `mint(address to, uint256 amount) external` — line 11

**test/src/concrete/StoxWrappedTokenVault.t.sol** (82 lines)
- `contract StoxWrappedTokenVaultTest is Test` — line 15
- `_deployer() internal returns (StoxWrappedTokenVaultBeaconSetDeployer)` — line 16
- `testConstructorDisablesInitializers() external` — line 27
- `testInitializeAddressAlwaysReverts(address asset) external` — line 34
- `testInitializeZeroAssetViaDeployer() external` — line 42
- `testInitializeZeroAssetDirect() external` — line 50
- `testInitializeSuccess() external` — line 60
- `testNameDelegation() external` — line 68
- `testSymbolDelegation() external` — line 76

**test/src/concrete/StoxWrappedTokenVaultV1.prod.base.t.sol** (88 lines)
- `contract StoxWrappedTokenVaultV1ProdBaseTest is Test` — line 15
- `_v1Beacon() internal returns (address)` — line 16
- `testProdV1ZeroAssetDoesNotRevert() external` — line 27
- `testProdV1OldBeaconSelectorWorks() external` — line 41
- `testProdV1DeploymentEventAfterInitialize() external` — line 59

**test/src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.t.sol** (86 lines)
- `contract StoxWrappedTokenVaultBeaconSetDeployerTest is Test` — line 15
- `testConstructZeroVaultImplementation(address initialOwner) external` — line 18
- `testConstructZeroBeaconOwner() external` — line 30
- `testConstructSuccess(address initialOwner) external` — line 42
- `testNewVaultZeroAsset(address initialOwner) external` — line 56
- `testNewVaultSuccess(address initialOwner) external` — line 71

**test/src/concrete/deploy/StoxUnifiedDeployer.t.sol** (104 lines)
- `contract StoxUnifiedDeployerTest is Test` — line 16
- `testStoxUnifiedDeployer(address asset, address vault, OffchainAssetReceiptVaultConfigV2 memory config) external` — line 17
- `testStoxUnifiedDeployerRevertsFirstDeployer(OffchainAssetReceiptVaultConfigV2 memory config) external` — line 52
- `testStoxUnifiedDeployerRevertsSecondDeployer(address asset, OffchainAssetReceiptVaultConfigV2 memory config) external` — line 72

**test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol** (128 lines)
- `contract StoxProdBaseTest is Test` — line 18
- `_checkAllOnChain() internal view` — line 20
- `_checkAllCreationBytecodes() internal view` — line 85
- `testProdStoxUnifiedDeployerFreshCodehash() external` — line 113
- `testProdCreationBytecodes() external view` — line 119
- `testProdDeployBase() external` — line 124

**test/src/lib/LibProdDeployV2.t.sol** (183 lines)
- `contract LibProdDeployV2Test is Test` — line 33
- Tests: `testDeployAddressStoxReceipt`, `testDeployAddressStoxReceiptVault`, `testDeployAddressStoxWrappedTokenVault`, `testDeployAddressStoxUnifiedDeployer`, `testCodehashStoxReceipt`, `testCodehashStoxReceiptVault`, `testCodehashStoxWrappedTokenVault`, `testCodehashStoxUnifiedDeployer`, `testCreationCodeStoxReceipt`, `testCreationCodeStoxReceiptVault`, `testCreationCodeStoxWrappedTokenVault`, `testCreationCodeStoxUnifiedDeployer`, `testRuntimeCodeStoxReceipt`, `testRuntimeCodeStoxReceiptVault`, `testRuntimeCodeStoxWrappedTokenVault`, `testRuntimeCodeStoxUnifiedDeployer`, `testGeneratedAddressStoxReceipt`, `testGeneratedAddressStoxReceiptVault`, `testGeneratedAddressStoxWrappedTokenVault`, `testGeneratedAddressStoxUnifiedDeployer`

**test/src/lib/LibProdDeployV1V2.t.sol** (49 lines)
- `contract LibProdDeployV1V2Test is Test` — line 15
- `testStoxReceiptCodehashV1EqualsV2() external pure` — line 17
- `testStoxReceiptVaultCodehashV1EqualsV2() external pure` — line 25
- `testStoxWrappedTokenVaultCodehashV1DiffersV2() external pure` — line 35
- `testStoxUnifiedDeployerCodehashV1EqualsV2() external pure` — line 43

---

## Prior Finding Status

| Prior ID | Status |
|---|---|
| P4-1 | FIXED — no bare `src/` imports in project-owned files |
| P4-2 | FIXED — mixed import styles resolved |
| P4-3 | FIXED — bare `lib/` path removed |
| P4-4 | FIXED — unused `LibExtrospectBytecode` import removed |
| P4-6 | DISMISSED — address constants serve as audit trail |

---

## Findings

### A02-P4-1: `Deploy.t.sol` imports a constant that no longer exists in `Deploy.sol` [HIGH]

**Location:** `test/script/Deploy.t.sol` lines 8 and 18; `script/Deploy.sol`

`test/script/Deploy.t.sol` imports and uses `DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET` from `script/Deploy.sol`. That constant was removed from `Deploy.sol` when the offchain-asset-receipt-vault-beacon-set deployment suite was removed. The test still imports it and asserts its value in `testDeploymentSuiteConstants()`.

**Impact:** Build fails to compile — `forge build` reports:
```
Error (2904): Declaration "DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET" not found in "script/Deploy.sol"
```
No tests can run.

**Severity:** HIGH (compilation failure)

**Recommendation:** Remove the import and the assertion line referencing `DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET` from `test/script/Deploy.t.sol`.

---

### A07-P4-2: Test files reference symbols removed from `StoxWrappedTokenVaultBeaconSetDeployer` source [HIGH]

**Location:**
- `test/src/concrete/StoxWrappedTokenVaultBeaconSetDeployer.t.sol` lines 8–11
- `test/src/concrete/StoxWrappedTokenVault.t.sol` lines 11–12, 18–23, 53

Three symbols were removed from `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` when the V2 Zoltu refactor removed the constructor:
1. `StoxWrappedTokenVaultBeaconSetDeployerConfig` struct
2. `ZeroVaultImplementation` error
3. `ZeroBeaconOwner` error

Additionally, the `iStoxWrappedTokenVaultBeacon()` public accessor (which exposed the `UpgradeableBeacon`) was removed.

The tests for these features were not updated to reflect the refactor. They compile against symbols that do not exist in the current source.

**Impact:** Compilation failure (same root cause as A02-P4-1 above — the entire test suite cannot compile).

The following tests can no longer compile or execute:
- `testConstructZeroVaultImplementation`
- `testConstructZeroBeaconOwner`
- `testConstructSuccess`
- `testNewVaultZeroAsset`
- `testNewVaultSuccess`
- `testInitializeZeroAssetDirect` (calls `deployer.iStoxWrappedTokenVaultBeacon()`)
- `_deployer()` helper in `StoxWrappedTokenVault.t.sol`

**Severity:** HIGH (compilation failure)

**Recommendation:** Update both test files to match the current V2 interface of `StoxWrappedTokenVaultBeaconSetDeployer`:
- Remove imports of `StoxWrappedTokenVaultBeaconSetDeployerConfig`, `ZeroVaultImplementation`, `ZeroBeaconOwner`
- Replace constructor calls with `new StoxWrappedTokenVaultBeaconSetDeployer()` (no args)
- Remove tests for constructor validation (`testConstructZeroVaultImplementation`, `testConstructZeroBeaconOwner`, `testConstructSuccess`) — the V2 constructor has no args and no validation
- Update `testInitializeZeroAssetDirect` to obtain the beacon address from the hardcoded constant `BEACON_ADDRESS` in the pointers file
- Update the `_deployer()` helper to not pass configuration

---

### A07-P4-3: Unused `IBeacon` import in `StoxWrappedTokenVaultBeaconSetDeployer.sol` [LOW]

**Location:** `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` line 5

```solidity
import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
```

`IBeacon` is imported but not referenced anywhere in the current file. It is a leftover from the V1 version of this contract that held an `IBeacon public immutable iStoxWrappedTokenVaultBeacon` state variable. This was previously noted as INFO (A07-P3-5 in Pass 3); elevated to LOW here because it is now one of several cleanup items needed after the V2 refactor, and it creates misleading context suggesting `IBeacon` is part of this contract's interface.

**Severity:** LOW

**Recommendation:** Remove `import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";` from line 5.

---

## Build Warnings

**forge build output:**

```
Error: Compiler run failed:
Error (2904): Declaration "DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET"
  not found in "script/Deploy.sol" (referenced as "../../script/Deploy.sol").
 --> test/script/Deploy.t.sol:6:1
```

The build does not compile. There are no build **warnings** to report because the build fails before warnings can be collected. Root cause is A02-P4-1 / A07-P4-2.

---

## Style Consistency Check

### Pragma versions

| File | Pragma |
|---|---|
| `src/concrete/**/*.sol` | `=0.8.25` |
| `src/lib/*.sol` | `^0.8.25` |
| `script/*.sol` | `=0.8.25` |
| `test/src/**/*.t.sol` | `=0.8.25` |
| `test/concrete/MockERC20.sol` | `^0.8.25` |
| `test/lib/LibTestProd.sol` | `^0.8.25` |

Test-utility files (`test/lib/`) and mock contracts (`test/concrete/`) use `^0.8.25` while test contracts use `=0.8.25`. This mirrors the `src/lib/` vs `src/concrete/` split and is intentional — no finding raised.

### Import path style

All project-owned imports use either relative paths or named remappings. No bare `src/` or `lib/` import paths found in project-owned source, test, or script files. (Prior findings P4-1 through P4-4 confirmed fixed.)

---

## Commented-out Code

No commented-out code found in project-owned files (src/, test/, script/). All `//` comment content is either NatSpec, rationale prose, or slither suppressions.

---

## Unused Imports

| File | Unused Import | Note |
|---|---|---|
| `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` | `IBeacon` | See A07-P4-3 |

---

## Test Utility Usage

`test/lib/LibTestProd.sol` provides `createSelectForkBase(Vm vm)`.

All fork test files that need Base fork setup correctly use `LibTestProd.createSelectForkBase(vm)`:
- `StoxWrappedTokenVaultV1ProdBaseTest` — line 17 and line 42
- `StoxProdBaseTest` — line 125

No duplication of the `createSelectForkBase` pattern found. All fork tests that need it use the utility.

---

## Dependency Consistency

All dependencies are managed via Foundry submodules in `foundry.toml`. No conflicting versions visible in project-owned code. Dependency consistency in submodule trees is outside scope of this pass.

---

## Summary

| ID | Severity | Title |
|---|---|---|
| A02-P4-1 | HIGH | `Deploy.t.sol` imports constant removed from `Deploy.sol`; build fails |
| A07-P4-2 | HIGH | `BeaconSetDeployer.t.sol` and `StoxWrappedTokenVault.t.sol` reference V1-era symbols not present in V2 source; build fails |
| A07-P4-3 | LOW | Unused `IBeacon` import leftover from V1 in `StoxWrappedTokenVaultBeaconSetDeployer.sol` |
