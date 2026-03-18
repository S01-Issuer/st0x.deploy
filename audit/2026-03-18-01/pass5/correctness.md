# Pass 5: Correctness / Intent Verification — st0x.deploy

**Date:** 2026-03-18
**Auditor:** Claude Sonnet 4.6
**Branch:** 2026-03-17-deploy
**HEAD:** cae23b2 (WIP: full Zoltu conversion — all contracts parameterless)

---

## Evidence of Thorough Reading

### A01 — script/BuildPointers.sol (64 lines)

**Contract:** `BuildPointers is Script` — line 19

**Functions:**
- `addressConstantString(address addr) internal pure returns (string memory)` — line 20
- `buildContractPointers(string memory name, bytes memory creationCode) internal` — line 31
- `run() external` — line 50

**Contracts built:**
- `StoxReceipt` (line 53)
- `StoxReceiptVault` (line 54)
- `StoxWrappedTokenVault` (line 55)
- `StoxWrappedTokenVaultBeacon` (line 58)
- `StoxWrappedTokenVaultBeaconSetDeployer` (line 59)
- `StoxOffchainAssetReceiptVaultBeaconSetDeployer` (line 61)
- `StoxUnifiedDeployer` (line 62)

---

### A02 — script/Deploy.sol (170 lines)

**File-level symbols:**
- `error UnknownDeploymentSuite(bytes32 suite)` — line 19
- `bytes32 constant DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET` — line 23
- `bytes32 constant DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET` — line 27
- `bytes32 constant DEPLOYMENT_SUITE_UNIFIED_DEPLOYER` — line 30

**Contract:** `Deploy is Script` — line 32

**State variables:**
- `mapping(string => mapping(address => bytes32)) internal depCodeHashes` — line 33

**Functions:**
- `deployWrappedTokenVaultBeaconSet() internal` — line 37 (deploys implementation, beacon, deployer via Zoltu)
- `deployUnifiedDeployer() internal` — line 88 (deploys StoxUnifiedDeployer via Zoltu)
- `deployOffchainAssetReceiptVaultBeaconSet() internal` — line 109 (deploys receipt+vault implementations + OARV deployer via Zoltu)
- `run() public` — line 157

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
- `constructor()` — line 34: calls `_disableInitializers()`
- `initialize(address asset) external pure returns (bytes32)` — line 41: always reverts with `InitializeSignatureFn()`
- `initialize(bytes calldata data) external initializer returns (bytes32)` — line 49: ABI-decodes asset, checks non-zero, calls `__ERC4626_init` + `__ERC20_init("","")`, emits event, returns `ICLONEABLE_V2_SUCCESS`
- `name() public view override(IERC20Metadata, ERC20Upgradeable) returns (string memory)` — line 61: delegates to `asset().name()` with "Wrapped " prefix
- `symbol() public view override(IERC20Metadata, ERC20Upgradeable) returns (string memory)` — line 66: delegates to `asset().symbol()` with "w" prefix

---

### A06 — src/concrete/deploy/StoxUnifiedDeployer.sol (45 lines)

**Contract:** `StoxUnifiedDeployer` — line 19

**Events:**
- `Deployment(address sender, address asset, address wrapper)` — line 25

**Functions:**
- `newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config) external` — line 35

Hardcodes `LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` and `LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER`.

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

Beacon address (`BEACON_ADDRESS`) is imported from `generated/StoxWrappedTokenVaultBeacon.pointers.sol` — a compile-time constant, no constructor.

---

### A08 — src/lib/LibProdDeployV1.sol (94 lines + embedded bytecodes)

**Library:** `LibProdDeployV1` — line 10

**Address constants:**
- `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER = 0x2191981Ca...` — line 13
- `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER = 0xeF6f9D21...` — line 18
- `STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION = 0x80A79767...` — line 25
- `STOX_UNIFIED_DEPLOYER = 0x821a71a3...` — line 34
- `STOX_RECEIPT_IMPLEMENTATION = 0xE7573879...` — line 39
- `STOX_RECEIPT_VAULT_IMPLEMENTATION = 0x8EFfCe5E...` — line 52

**Codehash constants:** `PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1`, `PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1`, `PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1`, `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1`, `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1`, `PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1`

**Bytecode constants:** `PROD_STOX_RECEIPT_CREATION_BYTECODE_V1`, `PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V1`, `PROD_STOX_WRAPPED_TOKEN_VAULT_CREATION_BYTECODE_V1`, `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1`, `PROD_STOX_UNIFIED_DEPLOYER_CREATION_BYTECODE_V1`, `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1`

**Note:** No `BEACON_INITIAL_OWNER` — moved to `LibProdDeploy`.

---

### A09 — src/lib/LibProdDeployV2.sol (76 lines)

**Library:** `LibProdDeployV2` — line 38

**Constants (all sourced from generated pointers):**
- `STOX_RECEIPT` / `STOX_RECEIPT_CODEHASH`
- `STOX_RECEIPT_VAULT` / `STOX_RECEIPT_VAULT_CODEHASH`
- `STOX_WRAPPED_TOKEN_VAULT` / `STOX_WRAPPED_TOKEN_VAULT_CODEHASH`
- `STOX_UNIFIED_DEPLOYER` / `STOX_UNIFIED_DEPLOYER_CODEHASH`
- `STOX_WRAPPED_TOKEN_VAULT_BEACON` / `STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH`
- `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` / `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH` — sourced from **placeholder** pointer file with `address(0)` / `bytes32(0)`
- `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` / `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH`

---

### Test files

**test/lib/LibTestProd.sol** — `library LibTestProd`; `createSelectForkBase(Vm vm)` (line 10); `uint256 constant PROD_TEST_BLOCK_NUMBER_BASE = 43482822` (line 7)

**test/script/Deploy.t.sol** — `contract DeployTest`; `testDeploymentSuiteConstants() external pure` (line 16); `testUnknownDeploymentSuiteReverts() external` (line 26)

**test/concrete/MockERC20.sol** — `contract MockERC20 is ERC20`; `constructor()` (line 9); `mint(address, uint256)` (line 11)

**test/src/concrete/StoxWrappedTokenVault.t.sol** — `contract StoxWrappedTokenVaultTest`; `_deployer()` (line 16); `testConstructorDisablesInitializers` (line 27); `testInitializeAddressAlwaysReverts` (line 34); `testInitializeZeroAssetViaDeployer` (line 42); `testInitializeZeroAssetDirect` (line 50); `testInitializeSuccess` (line 60); `testNameDelegation` (line 68); `testSymbolDelegation` (line 76)

**test/src/concrete/StoxWrappedTokenVaultV1.prod.base.t.sol** — `contract StoxWrappedTokenVaultV1ProdBaseTest`; `_v1Beacon()` (line 16); `testProdV1ZeroAssetDoesNotRevert` (line 27); `testProdV1OldBeaconSelectorWorks` (line 41); `testProdV1DeploymentEventAfterInitialize` (line 59)

**test/src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.t.sol** — `contract StoxWrappedTokenVaultBeaconSetDeployerTest`; `testConstructZeroVaultImplementation` (line 18); `testConstructZeroBeaconOwner` (line 30); `testConstructSuccess` (line 42); `testNewVaultZeroAsset` (line 56); `testNewVaultSuccess` (line 71)

**test/src/concrete/deploy/StoxUnifiedDeployer.t.sol** — `contract StoxUnifiedDeployerTest`; `testStoxUnifiedDeployer` (line 17); `testStoxUnifiedDeployerRevertsFirstDeployer` (line 52); `testStoxUnifiedDeployerRevertsSecondDeployer` (line 72)

**test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol** — `contract StoxProdBaseTest`; `_checkAllOnChain()` (line 20); `_checkAllCreationBytecodes()` (line 85); `testProdStoxUnifiedDeployerFreshCodehash` (line 113); `testProdCreationBytecodes` (line 119); `testProdDeployBase` (line 124)

**test/src/lib/LibProdDeployV2.t.sol** — `contract LibProdDeployV2Test`; 20 test functions covering: deploy address, codehash, creation code, runtime code, generated address — for StoxReceipt, StoxReceiptVault, StoxWrappedTokenVault, StoxUnifiedDeployer only

**test/src/lib/LibProdDeployV1V2.t.sol** — `contract LibProdDeployV1V2Test`; `testStoxReceiptCodehashV1EqualsV2` (line 17); `testStoxReceiptVaultCodehashV1EqualsV2` (line 25); `testStoxWrappedTokenVaultCodehashV1DiffersV2` (line 35); `testStoxUnifiedDeployerCodehashV1EqualsV2` (line 43)

---

## Findings

### A02-P5-1: `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` pointer is an ungenerated placeholder — runtime deployment will fail [HIGH]

**Location:**
- `src/generated/StoxOffchainAssetReceiptVaultBeaconSetDeployer.pointers.sol` lines 8–9
- `src/lib/LibProdDeployV2.sol` lines 29–32, 65–69
- `script/Deploy.sol` lines 143–153

The pointer file `StoxOffchainAssetReceiptVaultBeaconSetDeployer.pointers.sol` was created as a placeholder and has never been populated by running `BuildPointers.sol`:

```solidity
bytes32 constant BYTECODE_HASH = bytes32(0);
address constant DEPLOYED_ADDRESS = address(0);
```

`LibProdDeployV2` imports these values and exposes them as `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER = address(0)` and `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH = bytes32(0)`.

`Deploy.sol`'s `deployOffchainAssetReceiptVaultBeaconSet()` passes these zero values to `LibRainDeploy.deployAndBroadcast(...)` as `expectedAddress` and `expectedCodeHash`. `deployAndBroadcast` will:
1. Deploy via Zoltu (which produces a non-zero address)
2. Compare `deployedAddress != expectedAddress` (address(0)) → revert with `UnexpectedDeployedAddress`

The `offchain-asset-receipt-vault-beacon-set` deployment suite is therefore entirely broken at runtime.

**Impact:** The full V2 deployment flow cannot be executed; the `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` address/codehash in `LibProdDeployV2` are incorrect (zero).

**Severity:** HIGH

**Recommendation:** Run `forge script script/BuildPointers.sol` (which now includes `StoxOffchainAssetReceiptVaultBeaconSetDeployer` at line 61) to regenerate all pointer files, then commit the updated `StoxOffchainAssetReceiptVaultBeaconSetDeployer.pointers.sol` with real address and codehash.

---

### A07-P5-2: Tests reference removed V1-era symbols — build is broken [HIGH]

**Location:**
- `test/src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.t.sol` lines 8–11, 18–86
- `test/src/concrete/StoxWrappedTokenVault.t.sol` lines 11–12, 16–24, 53

The V2 refactor of `StoxWrappedTokenVaultBeaconSetDeployer` removed three symbols that test files still import and use:

| Symbol | Removed from | Test file using it |
|--------|---|---|
| `StoxWrappedTokenVaultBeaconSetDeployerConfig` struct | `StoxWrappedTokenVaultBeaconSetDeployer.sol` | Both test files |
| `ZeroVaultImplementation` error | same | `BeaconSetDeployer.t.sol` |
| `ZeroBeaconOwner` error | same | `BeaconSetDeployer.t.sol` |

Additionally, `StoxWrappedTokenVault.t.sol` line 53 calls `deployer.iStoxWrappedTokenVaultBeacon()` — a method that no longer exists on the V2 deployer (it was an immutable public variable in V1; V2 uses a compile-time constant instead).

The test functions that are broken and cannot compile:
- `testConstructZeroVaultImplementation`, `testConstructZeroBeaconOwner`, `testConstructSuccess` — test a constructor that no longer exists
- `testNewVaultZeroAsset`, `testNewVaultSuccess` — use removed config struct
- `_deployer()` helper in `StoxWrappedTokenVault.t.sol` — passes config struct
- `testInitializeZeroAssetDirect` — calls removed `iStoxWrappedTokenVaultBeacon()` accessor

**Impact:** The entire test suite cannot compile. No tests can run.

**Severity:** HIGH (confirmed from Pass 4)

**Recommendation:** Update both test files to match the current V2 interface:

In `BeaconSetDeployer.t.sol`:
- Remove imports of `StoxWrappedTokenVaultBeaconSetDeployerConfig`, `ZeroVaultImplementation`, `ZeroBeaconOwner`
- Delete `testConstructZeroVaultImplementation` and `testConstructZeroBeaconOwner` (V2 has no constructor validation — beacon is hardcoded at compile time)
- Rewrite `testConstructSuccess` to verify the deployer can be instantiated with `new StoxWrappedTokenVaultBeaconSetDeployer()` (no args)
- Rewrite `testNewVaultZeroAsset` / `testNewVaultSuccess` to create the deployer without config

In `StoxWrappedTokenVault.t.sol`:
- Remove `StoxWrappedTokenVaultBeaconSetDeployerConfig` import
- Change `_deployer()` to `return new StoxWrappedTokenVaultBeaconSetDeployer()`
- Update `testInitializeZeroAssetDirect` to obtain beacon address from `BEACON_ADDRESS` constant imported from `generated/StoxWrappedTokenVaultBeacon.pointers.sol`

---

### A07-P5-3: Unused `IBeacon` import in `StoxWrappedTokenVaultBeaconSetDeployer.sol` [LOW]

**Location:** `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` line 5

`IBeacon` is imported but never referenced in the current file — a leftover from the V1 version that held an `IBeacon public immutable iStoxWrappedTokenVaultBeacon`. The `IBeacon` interface is now irrelevant to this contract.

**Severity:** LOW

**Recommendation:** Remove `import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";`

---

### A09-P5-4: `LibProdDeployV2.t.sol` omits tests for three V2 constants [LOW]

**Location:** `test/src/lib/LibProdDeployV2.t.sol`

`LibProdDeployV2` defines seven contract groups but `LibProdDeployV2.t.sol` only covers four:

| Constant group | Tested |
|---|---|
| `STOX_RECEIPT` | Yes |
| `STOX_RECEIPT_VAULT` | Yes |
| `STOX_WRAPPED_TOKEN_VAULT` | Yes |
| `STOX_UNIFIED_DEPLOYER` | Yes |
| `STOX_WRAPPED_TOKEN_VAULT_BEACON` | **No** |
| `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | **No** |
| `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | **No** |

Missing test coverage means:
1. If `StoxWrappedTokenVaultBeacon` or `StoxWrappedTokenVaultBeaconSetDeployer` pointer files diverge from compiled bytecode, no test will catch it.
2. Once `StoxOffchainAssetReceiptVaultBeaconSetDeployer.pointers.sol` is regenerated (see A02-P5-1), its correctness will be unverified unless tests are added.

**Severity:** LOW

**Recommendation:** Add deploy-address, codehash, creation-code, runtime-code, and generated-address test groups for `StoxWrappedTokenVaultBeacon`, `StoxWrappedTokenVaultBeaconSetDeployer`, and `StoxOffchainAssetReceiptVaultBeaconSetDeployer` in `LibProdDeployV2.t.sol`.

---

### A09-P5-5: CHANGELOG describes removed intermediate V2 state for `StoxWrappedTokenVaultBeaconSetDeployer` [LOW]

**Location:** `CHANGELOG.md` under "V2 / StoxWrappedTokenVaultBeaconSetDeployer"

The CHANGELOG states:
> - Renamed immutable `I_STOX_WRAPPED_TOKEN_VAULT_BEACON` to `iStoxWrappedTokenVaultBeacon` (mixedCase convention).

This describes an intermediate V2 state that was subsequently removed. The final V2 `StoxWrappedTokenVaultBeaconSetDeployer` has **no immutable** at all; the beacon address is a compile-time constant imported from a pointer file. Neither the old `I_STOX_WRAPPED_TOKEN_VAULT_BEACON` immutable nor the renamed `iStoxWrappedTokenVaultBeacon` accessor exists in the deployed V2 source.

Additionally, the CHANGELOG does not mention two new V2-only contracts:
- `StoxWrappedTokenVaultBeacon` — new in V2, provides the `UpgradeableBeacon` with hardcoded owner and implementation
- `StoxOffchainAssetReceiptVaultBeaconSetDeployer` — new in V2, wraps the ethgild upstream deployer with hardcoded config

**Severity:** LOW

**Recommendation:** Update CHANGELOG V2 section for `StoxWrappedTokenVaultBeaconSetDeployer` to reflect the final design (compile-time constant beacon, no immutable, no public accessor). Add entries for `StoxWrappedTokenVaultBeacon` and `StoxOffchainAssetReceiptVaultBeaconSetDeployer`.

---

## Verification Results

### 2. Tests vs. claims

| Test | Claim | Correct? |
|---|---|---|
| `testZeroVaultAsset` (BeaconSetDeployer.t.sol) | Zero asset causes `ZeroVaultAsset` revert | Source line 41-43 confirms guard; test would be correct IF compiling |
| `testInitializeZeroAssetViaDeployer` (WrappedTokenVault.t.sol) | Zero asset reverts via deployer | Deployer guard at line 41-43; test cannot compile (see A07-P5-2) |
| `testInitializeZeroAssetDirect` | Zero asset reverts with `ZeroAsset` on direct proxy call | Vault guard at line 51 correct; test cannot compile |
| `testInitializeAddressAlwaysReverts` | `initialize(address)` always reverts with `InitializeSignatureFn` | Implementation at line 42-44 is correct |
| `testConstructorDisablesInitializers` | Constructor disables initializers | `_disableInitializers()` at line 35 is correct |
| `testProdV1ZeroAssetDoesNotRevert` | V1 allows `address(0)` in initialize without revert | Correctly documents V1 on-chain behavior (no ZeroAsset check) |
| `testProdV1OldBeaconSelectorWorks` | V1 exposes `I_STOX_WRAPPED_TOKEN_VAULT_BEACON()`, V2 does not | Correctly documents the renaming/removal |
| `testProdV1DeploymentEventAfterInitialize` | V1 emits Deployment AFTER initialize; V2 emits BEFORE | V2 source confirms CEI order (emit at line 48, initialize at line 50); test logic is correct |
| `testStoxUnifiedDeployer` | Emits `Deployment(sender, asset, wrapper)` and returns both | Logic correct; blocked by compilation failure |
| `testStoxUnifiedDeployerRevertsFirstDeployer` | First deployer revert propagates | Correct — no asset mocking needed; revert propagates directly |
| `testStoxUnifiedDeployerRevertsSecondDeployer` | Second deployer revert propagates | Correct — ZeroVaultAsset propagates through UnifiedDeployer |
| `testDeploymentSuiteConstants` | Suite constants match their keccak256 strings | All three constants verified correct at Deploy.sol lines 23-30 |
| `testUnknownDeploymentSuiteReverts` | Unknown suite reverts with `UnknownDeploymentSuite` | Correct; `else` branch at Deploy.sol line 167 |
| `testStoxWrappedTokenVaultCodehashV1DiffersV2` | V1 and V2 wrapped token vault codehashes differ | Correct — V2 adds ZeroAsset check which changes bytecode |
| `testStoxUnifiedDeployerCodehashV1EqualsV2` | V1 and V2 unified deployer codehashes are equal | Correct — source is unchanged (CHANGELOG: "No changes from V1") |

### 3. Constants and magic numbers

| Constant | Value | Consistent with documentation? |
|---|---|---|
| `LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | `0x2191981Ca2477B745870cC307cbEB4cB2967ACe3` | Matches Basescan link in comment |
| `LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | `0xeF6f9D21ED2E2742bfd3dFcf67829e4855884faB` | Matches Basescan link |
| `LibProdDeployV1.STOX_UNIFIED_DEPLOYER` | `0x821a71a313bdDDc94192CF0b5F6f5bC31Ac75853` | Matches Basescan link and CHANGELOG |
| `LibProdDeploy.BEACON_INITIAL_OWNER` | `0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b` | Matches Basescan link (rainlang.eth) |
| `LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | `address(0)` | **Placeholder — NOT the real address** (see A02-P5-1) |
| `DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET` | `keccak256("offchain-asset-receipt-vault-beacon-set")` | Correct per declaration |
| `ICLONEABLE_V2_SUCCESS` | `keccak256("ICloneableV2.initialize")` | Confirmed in upstream interface definition |

### 4. NatSpec vs. implementation

- **StoxReceiptVault** (A04): "Currently there are no modifications to the base contract" — correct, empty body.
- **StoxReceipt** (A03): "Currently there are no modifications to the base contract" — correct, empty body.
- **StoxWrappedTokenVault.initialize(address)** (A05, line 38-40): NatSpec says "always revert" — implementation always reverts with `InitializeSignatureFn()`. Correct.
- **StoxWrappedTokenVault.initialize(bytes)** (A05, line 46-48): NatSpec says `data` is `abi.encode(address asset)` — implementation decodes as `(address)`. Correct.
- **StoxWrappedTokenVaultBeaconSetDeployer** (A07, line 17-25): NatSpec says "no constructor args" — implementation has no constructor. Correct.
- **StoxUnifiedDeployer** (A06, line 14-18): NatSpec says "beacon sets are hardcoded" — implementation uses `LibProdDeployV1` hardcoded addresses. Correct.

### 5. Error conditions vs. triggers

| Error | Trigger condition | Correctly triggered? |
|---|---|---|
| `ZeroAsset` | `asset == address(0)` in `StoxWrappedTokenVault.initialize(bytes)` | Yes — line 51 |
| `ZeroVaultAsset` | `asset == address(0)` in `StoxWrappedTokenVaultBeaconSetDeployer.newStoxWrappedTokenVault` | Yes — line 41-43 |
| `InitializeVaultFailed` | `initialize(...)` returns something other than `ICLONEABLE_V2_SUCCESS` | Yes — line 50-52 |
| `InitializeSignatureFn` | `StoxWrappedTokenVault.initialize(address)` is called | Yes — line 42-44 (always) |
| `UnknownDeploymentSuite` | `DEPLOYMENT_SUITE` env var doesn't match known suites | Yes — else branch in `run()` |

### 6. Interface conformance: ICloneableV2

`StoxWrappedTokenVault` satisfies `ICloneableV2`:

- `initialize(address)` — always reverts with `InitializeSignatureFn()` as required (line 41-44)
- `initialize(bytes calldata data) returns (bytes32)` — ABI-decodes data, initializes, returns `ICLONEABLE_V2_SUCCESS` (line 49-58)
- Re-initialization prevented: `initializer` modifier on `initialize(bytes)` combined with `_disableInitializers()` in constructor
- `ICLONEABLE_V2_SUCCESS = keccak256("ICloneableV2.initialize")` matches the upstream constant

ERC4626 conformance:
- `name()` and `symbol()` are overridden to delegate to the underlying asset (lines 61-68) — these would otherwise return empty strings since `__ERC20_init("", "")` is called with empty strings. This is correct and intentional.
- `__ERC4626_init` and `__ERC20_init` are called separately as required (ERC4626Upgradeable does not call `__ERC20_init` internally in OZ v5).

### 7. Cross-file consistency

| Check | Result |
|---|---|
| V1 and V2 codehashes for `StoxReceipt` | Expected equal — `testStoxReceiptCodehashV1EqualsV2` asserts this |
| V1 and V2 codehashes for `StoxReceiptVault` | Expected equal — `testStoxReceiptVaultCodehashV1EqualsV2` asserts this |
| V1 and V2 codehashes for `StoxWrappedTokenVault` | Expected DIFFERENT — `testStoxWrappedTokenVaultCodehashV1DiffersV2` asserts this (V2 adds `ZeroAsset` guard) |
| V1 and V2 codehashes for `StoxUnifiedDeployer` | Expected equal — `testStoxUnifiedDeployerCodehashV1EqualsV2` asserts this (no source changes) |
| `StoxUnifiedDeployer` imports `LibProdDeployV1` for deployer addresses | Correct — the deployed V2 instance intentionally calls V1 beacon deployers (V1 on-chain deployment still used) |
| `LibProdDeployV2` OARV deployer constants = `address(0)` / `bytes32(0)` | **Inconsistent** — placeholder not generated (see A02-P5-1) |
| `BuildPointers.sol` includes `StoxOffchainAssetReceiptVaultBeaconSetDeployer` | Yes — line 61, but pointer file not regenerated |

---

## Summary

| ID | Severity | Title |
|---|---|---|
| A02-P5-1 | HIGH | OARV deployer pointer placeholder — `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER = address(0)` makes V2 deployment suite fail at runtime |
| A07-P5-2 | HIGH | Test files reference removed V1-era symbols — build is broken (confirmed from Pass 4) |
| A07-P5-3 | LOW | Unused `IBeacon` import in `StoxWrappedTokenVaultBeaconSetDeployer.sol` |
| A09-P5-4 | LOW | `LibProdDeployV2.t.sol` missing tests for beacon, beacon-set deployer, and OARV deployer |
| A09-P5-5 | LOW | CHANGELOG describes removed intermediate V2 state; two new V2 contracts not documented |
