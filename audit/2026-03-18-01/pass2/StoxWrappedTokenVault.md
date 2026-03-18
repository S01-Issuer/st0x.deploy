# Pass 2 — Test Coverage: StoxWrappedTokenVault.sol

**Agent:** A05
**File:** `src/concrete/StoxWrappedTokenVault.sol`

---

## 1. Evidence of Thorough Reading

### Source file: `src/concrete/StoxWrappedTokenVault.sol`

**Contract:** `StoxWrappedTokenVault` (line 28)

**Functions:**
- `constructor()` — line 34: calls `_disableInitializers()`
- `initialize(address asset)` — line 41: always reverts with `InitializeSignatureFn()`
- `initialize(bytes calldata data)` — line 49: real initializer; decodes asset, reverts with `ZeroAsset()` if zero, calls `__ERC4626_init` and `__ERC20_init`, emits `StoxWrappedTokenVaultInitialized`, returns `ICLONEABLE_V2_SUCCESS`
- `name()` — line 61: returns `"Wrapped " + asset.name()`
- `symbol()` — line 66: returns `"w" + asset.symbol()`

**Events:**
- `StoxWrappedTokenVaultInitialized(address indexed sender, address indexed asset)` — line 32

**Errors:**
- `ZeroAsset()` — line 12

**Interfaces implemented:**
- `ERC4626Upgradeable` (via inheritance)
- `ICloneableV2`

---

### Test file: `test/src/concrete/StoxWrappedTokenVault.t.sol`

**Contract:** `StoxWrappedTokenVaultTest` (line 15)

**Helper functions:**
- `_deployer()` — line 16: creates impl + `StoxWrappedTokenVaultBeaconSetDeployer`

**Test functions:**
- `testConstructorDisablesInitializers()` — line 27: calls `impl.initialize(abi.encode(address(1)))`, bare `vm.expectRevert()`
- `testInitializeAddressAlwaysReverts(address asset)` — line 34: fuzz, specific `InitializeSignatureFn` selector
- `testInitializeZeroAssetViaDeployer()` — line 42: bare `vm.expectRevert()`, calls through deployer
- `testInitializeZeroAssetDirect()` — line 50: specific `ZeroAsset.selector`, creates raw `BeaconProxy`
- `testInitializeSuccess()` — line 60: checks `vault.asset()` equals the mock
- `testNameDelegation()` — line 68: asserts `"Wrapped Test Token"`
- `testSymbolDelegation()` — line 76: asserts `"wTT"`

**Imports used:**
- `MockERC20` — `test/concrete/MockERC20.sol` (name="Test Token", symbol="TT")
- `StoxWrappedTokenVaultBeaconSetDeployer`
- `BeaconProxy`

---

### Test file: `test/src/concrete/StoxWrappedTokenVaultV1.prod.base.t.sol`

**Contract:** `StoxWrappedTokenVaultV1ProdBaseTest` (line 15) — fork tests

**Test functions:**
- `testProdV1ZeroAssetDoesNotRevert()` — line 27: V1 accepts zero asset (behavioral diff)
- `testProdV1OldBeaconSelectorWorks()` — line 41: V1 selector vs V2 rename
- `testProdV1DeploymentEventAfterInitialize()` — line 59: V1 event ordering

---

### Additional coverage found (`test/src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.t.sol`):

Tests the deployer layer — exercises `newStoxWrappedTokenVault` which calls `initialize(bytes)` via beacon proxy. Includes specific `ZeroVaultAsset` revert test.

---

## 2. Coverage Analysis

### `constructor()` — disables initializers
- **Tested:** Yes — `testConstructorDisablesInitializers()` verifies that calling `initialize(bytes)` on the implementation reverts.
- **Issue:** Uses bare `vm.expectRevert()` (line 29). The correct specific error is `Initializable.InvalidInitialization()` (OZ v5 error). This masks any other panic as passing.

### `initialize(address)` — always reverts
- **Tested:** Yes — `testInitializeAddressAlwaysReverts(address)` uses the specific `ICloneableV2.InitializeSignatureFn` selector. Coverage is adequate and properly specific.

### `initialize(bytes)` — zero asset
- **Tested via deployer:** `testInitializeZeroAssetViaDeployer()` uses bare `vm.expectRevert()` (line 44). The revert at the deployer layer is `ZeroVaultAsset` (from `StoxWrappedTokenVaultBeaconSetDeployer`), not `ZeroAsset`. Using a bare expectRevert masks which contract reverted and why.
- **Tested via direct proxy:** `testInitializeZeroAssetDirect()` correctly uses `abi.encodeWithSelector(ZeroAsset.selector)`. Adequate.

### `initialize(bytes)` — happy path return value
- **Not tested:** The test `testInitializeSuccess()` only checks `vault.asset()`. The return value `ICLONEABLE_V2_SUCCESS` is never asserted. The `ICloneableV2` interface contract specifies this return value must be exactly `ICLONEABLE_V2_SUCCESS` — it is untested.

### `StoxWrappedTokenVaultInitialized` event emission
- **Not tested:** No test asserts that the event is emitted with the correct `sender` and `asset` arguments when `initialize(bytes)` succeeds. The event is only checked in the V1 prod fork test as a topic hash (event ordering), not with `vm.expectEmit`.

### `name()` — delegation
- **Tested:** `testNameDelegation()` asserts `"Wrapped Test Token"`. Adequate.

### `symbol()` — delegation
- **Tested:** `testSymbolDelegation()` asserts `"wTT"`. Adequate.

### ERC4626 operations (deposit, withdraw, mint, redeem, convert, preview, max)
- **Not tested:** No test in `StoxWrappedTokenVault.t.sol` or the V1 fork file exercises ERC4626 operations — deposit, withdraw, mint, redeem, `convertToShares`, `convertToAssets`, `previewDeposit`, `previewWithdraw`, `previewMint`, `previewRedeem`, `maxDeposit`, `maxMint`. These are inherited from `ERC4626Upgradeable` but the vault overrides `name()` and `symbol()`, and the ERC4626 math depends on the underlying asset's `decimals()` which is also not tested.

### `asset()` return value post-init
- **Tested:** `testInitializeSuccess()` asserts `vault.asset()` equals the mock. Adequate.

### Double-initialization guard
- **Not tested:** No test attempts to call `initialize(bytes)` twice on the same proxy and asserts `InvalidInitialization()`.

---

## 3. Findings

### A05-1: Bare `vm.expectRevert()` in `testConstructorDisablesInitializers`
**Severity:** LOW
**File:** `test/src/concrete/StoxWrappedTokenVault.t.sol`, line 29

`testConstructorDisablesInitializers` uses a bare `vm.expectRevert()` with no error selector. OZ v5 `_disableInitializers` sets `_initialized` to `type(uint64).max`, causing subsequent calls to revert with `Initializable.InvalidInitialization()`. The specific selector should be used so the test fails if a different revert reason occurs (e.g., a different guard replacing the OZ guard in a future upgrade would silently pass this test).

**Fix file:** `.fixes/A05-1.md`

---

### A05-2: Bare `vm.expectRevert()` in `testInitializeZeroAssetViaDeployer`
**Severity:** LOW
**File:** `test/src/concrete/StoxWrappedTokenVault.t.sol`, line 44

`testInitializeZeroAssetViaDeployer` uses a bare `vm.expectRevert()`. The deployer's check at `StoxWrappedTokenVaultBeaconSetDeployer.sol:42` reverts with `ZeroVaultAsset()`. This test should use `abi.encodeWithSelector(ZeroVaultAsset.selector)` to pin the exact error and ensure it originates from the deployer, not from any other source.

**Fix file:** `.fixes/A05-2.md`

---

### A05-3: `ICLONEABLE_V2_SUCCESS` return value never asserted
**Severity:** LOW
**File:** `test/src/concrete/StoxWrappedTokenVault.t.sol`

`initialize(bytes calldata data)` is contractually required to return `ICLONEABLE_V2_SUCCESS` per the `ICloneableV2` interface. No test calls `initialize(bytes)` directly and asserts the return value equals `ICLONEABLE_V2_SUCCESS`. The only success-path test (`testInitializeSuccess`) calls through the deployer and only checks `vault.asset()`, so the return value is discarded. A contract returning the wrong magic value would silently pass all existing tests.

**Fix file:** `.fixes/A05-3.md`

---

### A05-4: `StoxWrappedTokenVaultInitialized` event not asserted with `vm.expectEmit`
**Severity:** LOW
**File:** `test/src/concrete/StoxWrappedTokenVault.t.sol`

No test uses `vm.expectEmit` to verify that `StoxWrappedTokenVaultInitialized` is emitted with the correct `sender` and `asset` indexed arguments on successful initialization. If the event signature, arguments, or emission were accidentally removed or changed (e.g., wrong address passed), all existing tests would still pass.

**Fix file:** `.fixes/A05-4.md`

---

### A05-5: No test for double-initialization revert
**Severity:** LOW
**File:** `test/src/concrete/StoxWrappedTokenVault.t.sol`

There is no test that initializes a proxy successfully and then attempts a second `initialize(bytes)` call, verifying it reverts with `Initializable.InvalidInitialization()`. The `initializer` modifier guard is an important invariant — a vault that can be re-initialized would allow an attacker to replace the underlying asset.

**Fix file:** `.fixes/A05-5.md`

---

### A05-6: ERC4626 operations entirely untested
**Severity:** MEDIUM
**File:** `test/src/concrete/StoxWrappedTokenVault.t.sol`

No test exercises any ERC4626 operation (deposit, withdraw, mint, redeem, convertToShares, convertToAssets, previewDeposit, previewWithdraw, previewMint, previewRedeem, maxDeposit, maxMint, maxWithdraw, maxRedeem, totalAssets). The vault is intended to wrap a `StoxReceiptVault` as its asset and the ERC4626 implementation is the central mechanism of the contract. While these are inherited from OZ's `ERC4626Upgradeable`, the vault's custom initialization (especially the `__ERC4626_init` call binding the asset) means any misconfiguration of the asset binding would go undetected. Functional smoke tests are needed to verify the ERC4626 surface works end-to-end after initialization.

**Fix file:** `.fixes/A05-6.md`

---

## 4. Coverage Summary Table

| Path | Covered | Notes |
|---|---|---|
| `constructor()` disables initializers | Partially | Bare revert, should be `InvalidInitialization` |
| `initialize(address)` always reverts | Yes | Specific selector used |
| `initialize(bytes)` ZeroAsset direct | Yes | Specific selector |
| `initialize(bytes)` ZeroAsset via deployer | Partially | Bare revert |
| `initialize(bytes)` success: asset set | Yes | |
| `initialize(bytes)` success: return value | No | `ICLONEABLE_V2_SUCCESS` never checked |
| `initialize(bytes)` event emission | No | `StoxWrappedTokenVaultInitialized` not `expectEmit`-tested |
| `initialize(bytes)` double-init guard | No | No re-init test |
| `name()` delegation | Yes | |
| `symbol()` delegation | Yes | |
| ERC4626 operations | No | deposit/withdraw/mint/redeem/previews all absent |
