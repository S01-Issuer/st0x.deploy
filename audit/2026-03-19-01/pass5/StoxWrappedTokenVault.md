# Pass 5: Correctness / Intent Verification -- `src/concrete/StoxWrappedTokenVault.sol`

**Agent:** A05
**Date:** 2026-03-19
**File:** `src/concrete/StoxWrappedTokenVault.sol` (71 lines)
**Test files:**
- `test/src/concrete/StoxWrappedTokenVault.t.sol` (300 lines)
- `test/src/concrete/StoxWrappedTokenVaultV2.t.sol` (74 lines)

---

## Evidence of Thorough Reading

### Source: `src/concrete/StoxWrappedTokenVault.sol`

**Contract:** `StoxWrappedTokenVault` (line 29) -- inherits `ERC4626Upgradeable`, `ICloneableV2`

**Imports:**

| Symbol | Source | Line |
|---|---|---|
| `ERC4626Upgradeable` | `openzeppelin-contracts-upgradeable/.../ERC4626Upgradeable.sol` | 6-7 |
| `ERC20Upgradeable` | `openzeppelin-contracts-upgradeable/.../ERC20Upgradeable.sol` | 8 |
| `ICLONEABLE_V2_SUCCESS`, `ICloneableV2` | `rain.factory/interface/ICloneableV2.sol` | 9 |
| `IERC20Metadata` | `openzeppelin-contracts/.../IERC20Metadata.sol` | 10 |

**Errors (file scope):**
- `ZeroAsset()` (line 13) -- `@dev`: "Error raised when a zero address is provided for the vault asset."

**Events:**
- `StoxWrappedTokenVaultInitialized(address indexed sender, address indexed asset)` (line 33) -- `@dev`: "Emitted when the StoxWrappedTokenVault is initialized."

**Functions:**

| Function | Line | Visibility | Modifiers |
|---|---|---|---|
| `constructor()` | 36 | implicit public | calls `_disableInitializers()` |
| `initialize(address asset)` | 43 | `external pure` | -- (always reverts) |
| `initialize(bytes calldata data)` | 51 | `external` | `initializer` |
| `name()` | 63 | `public view` | `override(IERC20Metadata, ERC20Upgradeable)` |
| `symbol()` | 68 | `public view` | `override(IERC20Metadata, ERC20Upgradeable)` |

### Test: `test/src/concrete/StoxWrappedTokenVault.t.sol`

**Contract:** `StoxWrappedTokenVaultTest` (line 20) -- inherits `Test`

| Test Function | Line | What it claims to verify |
|---|---|---|
| `testConstructorDisablesInitializers` | 22 | Constructor prevents direct init on implementation |
| `testInitializeAddressAlwaysReverts` | 29 | `initialize(address)` always reverts with `InitializeSignatureFn` (fuzz) |
| `testInitializeZeroAssetViaDeployer` | 37 | Zero asset via deployer reverts with `ZeroVaultAsset` |
| `testInitializeZeroAssetDirect` | 46 | Zero asset directly on proxy reverts with `ZeroAsset` |
| `testInitializeSuccess` | 55 | Successful init via deployer, `asset()` returns correct address |
| `testInitializeReturnsCloneableV2Success` | 65 | Direct init returns `ICLONEABLE_V2_SUCCESS` |
| `testInitializeEmitsEvent` | 75 | Emits `StoxWrappedTokenVaultInitialized` with correct sender/asset |
| `testDoubleInitializeReverts` | 86 | Re-initialization reverts with `InvalidInitialization` |
| `testNameDelegation` | 97 | `name()` returns `"Wrapped Test Token"` |
| `testSymbolDelegation` | 107 | `symbol()` returns `"wTT"` |
| `testTotalAssetsInitiallyZero` | 117 | Fresh vault has zero `totalAssets()` |
| `testDepositMintSharesOneToOne` | 127 | Fuzz: deposit mints 1:1 shares at initial rate |
| `testWithdrawRoundTrip` | 149 | Fuzz: deposit then full withdraw recovers all assets |
| `testConvertRoundTrip` | 174 | Fuzz: `convertToAssets(convertToShares(x)) == x` on empty vault |
| `testPreviewDepositMatchesActual` | 188 | Fuzz: `previewDeposit` matches actual shares minted |
| `testPreviewWithdrawMatchesActual` | 210 | Fuzz: `previewWithdraw` matches actual shares burned |
| `testMaxDepositUnbounded` | 235 | `maxDeposit` returns `type(uint256).max` (fuzz) |
| `testMaxMintUnbounded` | 245 | `maxMint` returns `type(uint256).max` (fuzz) |
| `testMintShares` | 255 | Fuzz: `mint` consumes exactly `previewMint` assets |
| `testRedeemShares` | 277 | Fuzz: deposit then full redeem recovers all assets |

### Test: `test/src/concrete/StoxWrappedTokenVaultV2.t.sol`

**Contract:** `StoxWrappedTokenVaultV2Test` (line 17) -- inherits `Test`

| Test Function | Line | What it claims to verify |
|---|---|---|
| `testV2ZeroAssetReverts` | 20 | V2 deployer reverts on zero asset |
| `testV2DeploymentEventBeforeInitialize` | 29 | Deployment event emitted before init event (CEI fix from V1) |
| `testV2NewVaultSuccess` | 63 | Successful V2 vault: asset, name, symbol all correct |

---

## Correctness Verification

### 1. Contract name vs behavior

**Claim:** "StoxWrappedTokenVault" -- "An ERC-4626 compliant vault that wraps an underlying token."

**Verified:** The contract inherits `ERC4626Upgradeable`, making it ERC-4626 compliant. It wraps an underlying token set at initialization via `__ERC4626_init`. No ERC4626 virtual functions are overridden (only `name()` and `symbol()` from ERC20), so all vault mechanics (deposit, withdraw, mint, redeem, convertToShares, convertToAssets, totalAssets, etc.) are inherited unchanged from OZ v5.

### 2. Value capture in price, not supply

**Claim (NatSpec):** "The wrapper token as a vault never produces yield or rebases due to offchain events, therefore it captures the value in its price onchain rather than in its supply."

**Verified:** The inherited `totalAssets()` returns `IERC20(asset()).balanceOf(address(this))`. The share-to-asset conversion is `shares * (totalAssets + 1) / (totalSupply + 10^decimalsOffset)`. When the underlying receipt vault rebases (changing the balance held by this wrapper), `totalAssets()` changes while `totalSupply()` remains constant. This shifts the share price. The wrapper vault itself does not mint or burn shares except via explicit deposit/withdraw/mint/redeem, so supply changes only through user actions. The claim is correct.

### 3. ICloneableV2 conformance

**Claim:** Implements `ICloneableV2` with dual-initialize pattern.

**Verified:**
- `initialize(address)` (line 43): Declared `external pure`, unconditionally reverts with `InitializeSignatureFn()`. Matches ICloneableV2 requirement that typed overload MUST always revert.
- `initialize(bytes)` (line 51): Uses `initializer` modifier (one-time), decodes `abi.encode(address)`, returns `ICLONEABLE_V2_SUCCESS` on success. Matches ICloneableV2 specification.
- Constructor calls `_disableInitializers()`. Implementation cannot be initialized directly. Correct.
- Test `testInitializeAddressAlwaysReverts` fuzz-tests with arbitrary addresses. Correct.
- Test `testInitializeReturnsCloneableV2Success` asserts the return value. Correct.

### 4. Initialization sequence

**Code (lines 52-55):**
```
(address asset) = abi.decode(data, (address));
if (asset == address(0)) revert ZeroAsset();
__ERC4626_init(ERC20Upgradeable(asset));
__ERC20_init("", "");
```

**Verified:**
- Zero-address check occurs before any state mutation. If it reverts, the proxy remains uninitialized and re-initializable.
- `__ERC4626_init` sets the asset address and caches decimals via `_tryGetAssetDecimals`. It does not depend on ERC20 name/symbol.
- `__ERC20_init("", "")` sets empty strings in ERC20 storage. These are never used because `name()` and `symbol()` are overridden to delegate to the asset.
- The `initializer` modifier on `initialize(bytes)` ensures the entire function body is atomic with respect to the initialization flag -- partial failure (e.g., revert in `__ERC4626_init`) prevents the initialization flag from being set.
- The `abi.decode` will revert on malformed data (too short) before the `initializer` state change, leaving the proxy re-initializable. Correct.
- The cast `ERC20Upgradeable(asset)` wraps the address as a contract reference; `__ERC4626_init` accepts `IERC20` and `ERC20Upgradeable` is a valid subtype. Correct.

### 5. Dynamic name/symbol delegation

**Code (lines 63-70):**
```
function name() ... returns (string memory) {
    return string.concat("Wrapped ", IERC20Metadata(asset()).name());
}
function symbol() ... returns (string memory) {
    return string.concat("w", IERC20Metadata(asset()).symbol());
}
```

**Verified:**
- `asset()` reads the stored asset from ERC4626 storage (set during init). This is a `view` call.
- `IERC20Metadata(asset()).name()` and `.symbol()` make `STATICCALL` to the asset. If the asset does not implement `IERC20Metadata`, these revert. This is acceptable since the vault is purpose-built for wrapping receipt vaults that implement the interface.
- The `override(IERC20Metadata, ERC20Upgradeable)` correctly lists both base contracts that declare `name()`/`symbol()` in the inheritance chain. `ERC4626Upgradeable` does not override `name()` or `symbol()`, only `decimals()`.
- Test `testNameDelegation` verifies with MockERC20("Test Token", "TT") producing "Wrapped Test Token". Correct.
- Test `testSymbolDelegation` verifies producing "wTT". Correct.

### 6. Inherited ERC4626 mechanics

**Verified against OZ ERC4626Upgradeable (v5.5.0):**
- `decimals()` returns `_underlyingDecimals + _decimalsOffset()`. `_decimalsOffset()` returns 0 (not overridden). So vault decimals match the underlying asset's decimals cached at init. Correct.
- `totalAssets()` returns `IERC20(asset()).balanceOf(address(this))`. No override. Correct.
- `_convertToShares` uses `Floor` rounding for deposits (fewer shares minted, favors vault). Correct.
- `_convertToAssets` uses `Ceil` rounding for withdrawals (more shares burned, favors vault). Correct.
- Virtual shares: `totalSupply() + 10^0 = totalSupply() + 1` and `totalAssets() + 1`. OZ v5 inflation attack mitigation is active and not disabled. Correct.

### 7. Event emission

**Code (line 57):** `emit StoxWrappedTokenVaultInitialized(_msgSender(), asset);`

**Verified:**
- `_msgSender()` is from `ContextUpgradeable`, which returns `msg.sender` (no `ERC2771Context` in the inheritance chain). Correct.
- The event is emitted after state changes (`__ERC4626_init`, `__ERC20_init`) but before the return. Correct ordering.
- Both parameters are `indexed`, so they appear as topics[1] and topics[2] in the log.
- Test `testInitializeEmitsEvent` uses `vm.expectEmit(true, true, false, false, address(vault))` -- checks topics[1] (sender) and topics[2] (asset), skips topics[3] (none) and data (none). Correct.

### 8. Deployer integration (StoxWrappedTokenVaultBeaconSetDeployer)

**Verified:** The deployer (line 39-54 of the deployer file):
1. Checks `asset == address(0)`, reverts with `ZeroVaultAsset` (separate from the vault's own `ZeroAsset`).
2. Creates a `BeaconProxy` pointing to the hardcoded beacon.
3. Emits `Deployment` event BEFORE calling `initialize()` -- CEI pattern.
4. Calls `initialize(abi.encode(asset))` and checks for `ICLONEABLE_V2_SUCCESS` return.
5. Returns the vault.

This means there's a double zero-address check: the deployer checks first (`ZeroVaultAsset`), then the vault's own check (`ZeroAsset`) would fire if the deployer check were bypassed (e.g., direct proxy initialization). Both tests cover this: `testInitializeZeroAssetViaDeployer` tests the deployer path, `testInitializeZeroAssetDirect` tests the direct path. Correct.

### 9. Solidity version

`pragma solidity =0.8.25` -- exact pin for a concrete contract. Matches project convention.

### 10. Test correctness verification

| Test | Claim vs Reality |
|---|---|
| `testConstructorDisablesInitializers` | Creates `new StoxWrappedTokenVault()`, expects `InvalidInitialization` on `initialize(bytes)`. Correct: constructor calls `_disableInitializers()`. |
| `testInitializeAddressAlwaysReverts` | Fuzz with arbitrary address on implementation. Correct: `initialize(address)` is `pure` and always reverts regardless of caller/state. |
| `testInitializeZeroAssetViaDeployer` | Deploys beacon set, calls deployer with `address(0)`. Expects `ZeroVaultAsset`. Correct: deployer checks first. |
| `testInitializeZeroAssetDirect` | Creates bare BeaconProxy, calls `initialize(abi.encode(address(0)))`. Expects `ZeroAsset`. Correct: vault's own check fires. |
| `testInitializeSuccess` | Deploys via deployer with MockERC20, asserts `vault.asset() == address(asset)`. Correct. |
| `testInitializeReturnsCloneableV2Success` | Creates bare BeaconProxy, calls `initialize(bytes)` directly, asserts return == `ICLONEABLE_V2_SUCCESS`. Correct. |
| `testInitializeEmitsEvent` | Uses `vm.expectEmit` with topic checks matching sender/asset. Correct. |
| `testDoubleInitializeReverts` | Initializes once, tries again, expects `InvalidInitialization`. Correct. |
| `testNameDelegation` | MockERC20 name "Test Token" -> "Wrapped Test Token". Correct. |
| `testSymbolDelegation` | MockERC20 symbol "TT" -> "wTT". Correct. |
| `testDepositMintSharesOneToOne` | First deposit with virtual offset (1/1) -> 1:1 rate. Bounded to uint128 to avoid overflow. Correct. |
| `testWithdrawRoundTrip` | Deposit then withdraw same amount. At 1:1 rate, full recovery. Correct. |
| `testConvertRoundTrip` | On empty vault, `convertToAssets(convertToShares(x)) == x`. With Floor rounding in both directions and virtual 1/1, this holds. Correct. |
| `testPreviewDepositMatchesActual` | Previews then deposits, asserts match. Correct. |
| `testPreviewWithdrawMatchesActual` | Deposits, previews withdrawal, withdraws, asserts match. Correct. |
| `testMaxDepositUnbounded` | Returns `type(uint256).max`. Matches OZ default. Correct. |
| `testMaxMintUnbounded` | Returns `type(uint256).max`. Matches OZ default. Correct. |
| `testMintShares` | Previews mint, approves, mints, asserts assets consumed match preview. Correct. |
| `testRedeemShares` | Deposits, redeems all shares, asserts full asset recovery. Correct. |
| `testV2ZeroAssetReverts` | Same as `testInitializeZeroAssetViaDeployer`. Correct. |
| `testV2DeploymentEventBeforeInitialize` | Records logs, finds Deployment and Init events, asserts Deployment index < Init index. Correct CEI verification. |
| `testV2NewVaultSuccess` | Deploys via deployer, checks asset/name/symbol. Correct. |

---

## Findings

### A05-P5-1 -- INFO: `testConvertRoundTrip` only tests empty-vault exchange rate

**File:** `test/src/concrete/StoxWrappedTokenVault.t.sol`, line 174

The test `testConvertRoundTrip` asserts `convertToAssets(convertToShares(x)) == x`, but this is only tested on an empty vault where the exchange rate is 1:1 (due to virtual shares/assets both being 1). With a non-trivial exchange rate (after deposits and direct asset transfers), rounding losses would cause the round-trip to lose precision. This is expected ERC4626 behavior and not a bug, but the test name "round trip" could mislead readers into thinking the property holds universally. The same limitation was noted in the Pass 2 coverage analysis (A05-3) which recommended testing the share price change after direct asset transfer.

### A05-P5-2 -- INFO: `_msgSender()` vs `msg.sender` in event emission is functionally identical but obscures intent

**File:** `src/concrete/StoxWrappedTokenVault.sol`, line 57

The `StoxWrappedTokenVaultInitialized` event uses `_msgSender()` (from `ContextUpgradeable`) rather than `msg.sender`. Since the contract does not inherit `ERC2771Context` or any meta-transaction forwarder, `_msgSender()` always equals `msg.sender`. Using `_msgSender()` is not incorrect -- it is inherited from the OZ base chain -- but it implies meta-transaction support that is not present. This is purely informational as the behavior is identical.

---

## Non-Findings (Verified Correct)

- **Constructor `_disableInitializers()`**: Correctly prevents implementation initialization.
- **ICloneableV2 dual-initialize pattern**: Both overloads behave as specified.
- **Zero-address validation**: Present in both vault (`ZeroAsset`) and deployer (`ZeroVaultAsset`).
- **Initialization sequence**: ERC4626 init before ERC20 init, empty strings intentional.
- **Dynamic name/symbol**: Correctly delegates to underlying asset via IERC20Metadata.
- **Override specifiers**: `override(IERC20Metadata, ERC20Upgradeable)` correctly lists all bases.
- **ERC4626 rounding**: Inherited OZ v5 rounding is correct (Floor for deposits/convertToShares, Ceil for withdrawals/previewMint/previewWithdraw).
- **Inflation attack mitigation**: OZ v5 virtual shares (1) and virtual assets (1) active, not overridden.
- **Event emission**: Correct parameters, correct ordering (after state changes).
- **Deployer CEI pattern**: Deployment event before initialize call, verified by V2 test.
- **All 23 test assertions verified**: Each test correctly verifies what its NatSpec claims.

---

## Summary

| Check | Result |
|---|---|
| Contract name matches intent | Correct |
| NatSpec claims verified | All accurate |
| ICloneableV2 conformance | Correct |
| Initialization sequence | Correct |
| Dynamic name/symbol | Correct |
| ERC4626 mechanics (inherited) | Correct |
| Event emission | Correct |
| Test claims match reality | All 23 tests verified |
| Solidity version | Correct (=0.8.25) |
| New findings | 0 LOW+, 2 INFO |
