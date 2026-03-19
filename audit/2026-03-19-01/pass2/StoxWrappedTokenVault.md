# Pass 2: Test Coverage — StoxWrappedTokenVault.sol

**Agent:** A05
**Source file:** `src/concrete/StoxWrappedTokenVault.sol` (71 lines)
**Test files:**
- `test/src/concrete/StoxWrappedTokenVault.t.sol` (300 lines)
- `test/src/concrete/StoxWrappedTokenVaultV2.t.sol` (74 lines)
- `test/src/concrete/StoxWrappedTokenVaultV1.prod.base.t.sol` (83 lines)
**Test helpers:**
- `test/lib/LibTestDeploy.sol` (66 lines)
- `test/concrete/MockERC20.sol` (14 lines)

---

## Evidence of Thorough Reading

### Source: `src/concrete/StoxWrappedTokenVault.sol`

**Contract:** `StoxWrappedTokenVault` (line 29) — inherits `ERC4626Upgradeable`, `ICloneableV2`

**Errors (file scope):**
- `ZeroAsset()` (line 13)

**Events:**
- `StoxWrappedTokenVaultInitialized(address indexed sender, address indexed asset)` (line 33)

**Functions:**
| Function | Line | Visibility | Modifiers |
|---|---|---|---|
| `constructor()` | 36 | implicit public | calls `_disableInitializers()` |
| `initialize(address asset)` | 43 | `external pure` | — (always reverts) |
| `initialize(bytes calldata data)` | 51 | `external` | `initializer` |
| `name()` | 63 | `public view` | `override(IERC20Metadata, ERC20Upgradeable)` |
| `symbol()` | 68 | `public view` | `override(IERC20Metadata, ERC20Upgradeable)` |

**Imports:** `ERC4626Upgradeable`, `ERC20Upgradeable`, `ICLONEABLE_V2_SUCCESS`, `ICloneableV2`, `IERC20Metadata`

### Test: `test/src/concrete/StoxWrappedTokenVault.t.sol`

**Contract:** `StoxWrappedTokenVaultTest` (line 20) — inherits `Test`

**Imports:** `StoxWrappedTokenVault`, `ZeroAsset`, `ICloneableV2`, `ICLONEABLE_V2_SUCCESS`, `BeaconProxy`, `StoxWrappedTokenVaultBeaconSetDeployer`, `ZeroVaultAsset`, `StoxWrappedTokenVaultBeacon`, `LibRainDeploy`, `LibProdDeployV2`, `LibTestDeploy`, `Initializable`, `MockERC20`

**Functions:**
| Function | Line | What it tests |
|---|---|---|
| `testConstructorDisablesInitializers()` | 22 | Constructor calls `_disableInitializers()`, reverts with `InvalidInitialization` |
| `testInitializeAddressAlwaysReverts(address)` | 29 | `initialize(address)` always reverts with `InitializeSignatureFn` |
| `testInitializeZeroAssetViaDeployer()` | 37 | Zero asset via deployer reverts with `ZeroVaultAsset` |
| `testInitializeZeroAssetDirect()` | 46 | Zero asset direct on proxy reverts with `ZeroAsset` |
| `testInitializeSuccess()` | 55 | Successful init via deployer, asset check |
| `testInitializeReturnsCloneableV2Success()` | 65 | Direct init returns `ICLONEABLE_V2_SUCCESS` |
| `testInitializeEmitsEvent()` | 75 | Emit `StoxWrappedTokenVaultInitialized` verified |
| `testDoubleInitializeReverts()` | 86 | Re-initialization reverts with `InvalidInitialization` |
| `testNameDelegation()` | 97 | `name()` returns `"Wrapped Test Token"` |
| `testSymbolDelegation()` | 107 | `symbol()` returns `"wTT"` |
| `testTotalAssetsInitiallyZero()` | 117 | Fresh vault has zero totalAssets |
| `testDepositMintSharesOneToOne(uint256)` | 127 | Fuzz: deposit mints 1:1 shares, checks balances |
| `testWithdrawRoundTrip(uint256)` | 149 | Fuzz: deposit then withdraw round-trip |
| `testConvertRoundTrip(uint256)` | 174 | Fuzz: convertToShares/convertToAssets inverse |
| `testPreviewDepositMatchesActual(uint256)` | 188 | Fuzz: previewDeposit matches actual deposit |
| `testPreviewWithdrawMatchesActual(uint256)` | 210 | Fuzz: previewWithdraw matches actual withdraw |
| `testMaxDepositUnbounded(address)` | 235 | maxDeposit returns `type(uint256).max` |
| `testMaxMintUnbounded(address)` | 245 | maxMint returns `type(uint256).max` |
| `testMintShares(uint256)` | 255 | Fuzz: mint specific shares, verify assets consumed |
| `testRedeemShares(uint256)` | 277 | Fuzz: deposit then redeem round-trip |

### Test: `test/src/concrete/StoxWrappedTokenVaultV2.t.sol`

**Contract:** `StoxWrappedTokenVaultV2Test` (line 17) — inherits `Test`

**Imports:** `StoxWrappedTokenVault`, `ZeroAsset`, `StoxWrappedTokenVaultBeaconSetDeployer`, `ZeroVaultAsset`, `LibProdDeployV2`, `LibTestDeploy`, `MockERC20`, `Vm`

**Functions:**
| Function | Line | What it tests |
|---|---|---|
| `testV2ZeroAssetReverts()` | 20 | V2 deployer reverts on zero asset |
| `testV2DeploymentEventBeforeInitialize()` | 29 | Deployment event emitted before init event (CEI) |
| `testV2NewVaultSuccess()` | 63 | Successful V2 vault creation, name/symbol/asset |

### Test: `test/src/concrete/StoxWrappedTokenVaultV1.prod.base.t.sol`

**Contract:** `StoxWrappedTokenVaultV1ProdBaseTest` (line 15) — inherits `Test`

**Imports:** `LibProdDeployV1`, `LibTestProd`, `IBeacon`, `BeaconProxy`, `ICLONEABLE_V2_SUCCESS`, `Vm`

**Functions:**
| Function | Line | What it tests |
|---|---|---|
| `_v1Beacon()` | 16 | Helper: fork Base, get V1 beacon address |
| `testProdV1ZeroAssetDoesNotRevert()` | 26 | V1 allows zero asset (documents V2 fix) |
| `testProdV1OldBeaconSelectorWorks()` | 39 | V1 selector `I_STOX_WRAPPED_TOKEN_VAULT_BEACON()` works |
| `testProdV1DeploymentEventAfterInitialize()` | 55 | V1 emits Deployment after init (V2 reverses order) |

### Helper: `test/lib/LibTestDeploy.sol`

**Library:** `LibTestDeploy` (line 24)

**Functions:**
| Function | Line | What it does |
|---|---|---|
| `deployWrappedTokenVaultBeaconSet(Vm)` | 25 | Etches Zoltu factory, deploys vault + beacon + deployer via Zoltu, asserts address matches `LibProdDeployV2` |
| `deployOffchainAssetReceiptVaultBeaconSet(Vm)` | 43 | Deploys receipt + receipt vault + OARV deployer |
| `deployAll(Vm)` | 59 | Deploys both beacon sets + unified deployer |

### Helper: `test/concrete/MockERC20.sol`

**Contract:** `MockERC20` (line 8) — inherits `ERC20("Test Token", "TT")`

**Functions:**
| Function | Line | What it does |
|---|---|---|
| `constructor()` | 9 | Initializes with name "Test Token", symbol "TT" |
| `mint(address, uint256)` | 11 | Public mint for testing |

---

## Verification of Previously-Fixed Gaps

The prior audit (A05-1 through A05-6) identified these gaps which have all been fixed:

1. **A05-1 (bare `vm.expectRevert` in constructor test):** FIXED. `testConstructorDisablesInitializers` (line 24) now uses `Initializable.InvalidInitialization.selector`.
2. **A05-2 (bare `vm.expectRevert` in zero asset via deployer):** FIXED. `testInitializeZeroAssetViaDeployer` (line 39) now uses `ZeroVaultAsset.selector`.
3. **A05-3 (`ICLONEABLE_V2_SUCCESS` return never asserted):** FIXED. `testInitializeReturnsCloneableV2Success` (line 65) calls `initialize(bytes)` directly on a proxy and asserts the return value equals `ICLONEABLE_V2_SUCCESS`.
4. **A05-4 (event not asserted):** FIXED. `testInitializeEmitsEvent` (line 75) uses `vm.expectEmit` to verify `StoxWrappedTokenVaultInitialized` with sender and asset.
5. **A05-5 (no double-init test):** FIXED. `testDoubleInitializeReverts` (line 86) initializes a proxy, then asserts a second call reverts with `InvalidInitialization`.
6. **A05-6 (ERC4626 operations untested):** FIXED. Tests now cover deposit, withdraw, mint, redeem, totalAssets, convertToShares, convertToAssets, previewDeposit, previewWithdraw, maxDeposit, maxMint with fuzz testing.

---

## Coverage Analysis

### Source functions and their test coverage:

| Source Function | Tested? | Test(s) |
|---|---|---|
| `constructor()` | Yes | `testConstructorDisablesInitializers` |
| `initialize(address)` | Yes | `testInitializeAddressAlwaysReverts` (fuzz) |
| `initialize(bytes)` — happy path | Yes | `testInitializeSuccess`, `testInitializeReturnsCloneableV2Success`, `testInitializeEmitsEvent` |
| `initialize(bytes)` — zero asset | Yes | `testInitializeZeroAssetViaDeployer`, `testInitializeZeroAssetDirect` |
| `initialize(bytes)` — double init | Yes | `testDoubleInitializeReverts` |
| `name()` | Yes | `testNameDelegation`, `testV2NewVaultSuccess` |
| `symbol()` | Yes | `testSymbolDelegation`, `testV2NewVaultSuccess` |
| Inherited `deposit()` | Yes | `testDepositMintSharesOneToOne` (fuzz) |
| Inherited `withdraw()` | Yes | `testWithdrawRoundTrip` (fuzz) |
| Inherited `mint()` | Yes | `testMintShares` (fuzz) |
| Inherited `redeem()` | Yes | `testRedeemShares` (fuzz) |
| Inherited `totalAssets()` | Yes | `testTotalAssetsInitiallyZero`, implicitly in deposit/withdraw tests |
| Inherited `convertToShares()` | Yes | `testConvertRoundTrip` (fuzz) |
| Inherited `convertToAssets()` | Yes | `testConvertRoundTrip` (fuzz) |
| Inherited `previewDeposit()` | Yes | `testPreviewDepositMatchesActual` (fuzz) |
| Inherited `previewWithdraw()` | Yes | `testPreviewWithdrawMatchesActual` (fuzz) |
| Inherited `maxDeposit()` | Yes | `testMaxDepositUnbounded` (fuzz) |
| Inherited `maxMint()` | Yes | `testMaxMintUnbounded` (fuzz) |
| Inherited `previewMint()` | Partially | Used in `testMintShares` but only at 1:1 rate |
| Inherited `previewRedeem()` | No | Not tested |
| Inherited `maxWithdraw()` | No | Not tested |
| Inherited `maxRedeem()` | No | Not tested |

---

## Findings

### A05-1 — LOW: `previewRedeem` not tested

**File:** `test/src/concrete/StoxWrappedTokenVault.t.sol`

The test suite covers `previewDeposit` and `previewWithdraw` against actual operations, but `previewRedeem` is never tested. The ERC4626 spec requires `previewRedeem` to return the exact amount of assets that would be received for a given share amount. While this is inherited from OZ, the test suite already tests the other three preview functions, making this an inconsistency in coverage. If a future override or OZ upgrade changed rounding behavior for `previewRedeem`, no test would catch the regression.

### A05-2 — LOW: `maxWithdraw` and `maxRedeem` not tested

**File:** `test/src/concrete/StoxWrappedTokenVault.t.sol`

`maxDeposit` and `maxMint` are both tested to return `type(uint256).max`. However, `maxWithdraw(owner)` and `maxRedeem(owner)` are never tested. These functions are state-dependent (they should return the owner's actual withdrawable/redeemable amounts based on their share balance). Testing these after a deposit would verify the vault correctly reports withdrawal limits, which is important for DeFi integrators that check max amounts before calling `withdraw`/`redeem`.

### A05-3 — LOW: No test for ERC4626 share price change after direct asset transfer (donation/rebase scenario)

**File:** `test/src/concrete/StoxWrappedTokenVault.t.sol`

The vault's stated purpose is to "capture value in its price onchain rather than in its supply." All ERC4626 fuzz tests operate at the initial 1:1 exchange rate. No test verifies that the share price changes correctly when the underlying asset balance changes independent of deposit/withdraw (e.g., via a direct `asset.transfer()` to the vault simulating a rebase or dividend). This is the core value proposition of the vault. A test that deposits, then sends additional assets directly to the vault, then verifies that `convertToAssets(shares)` returns more than the original deposit amount would confirm the price-capture mechanism works through the proxy.

### A05-4 — INFO: `initialize(bytes)` with malformed data not tested

**File:** `test/src/concrete/StoxWrappedTokenVault.t.sol`

No test provides malformed `bytes` data to `initialize(bytes)` (e.g., empty bytes, wrong length, extra trailing data). The `abi.decode(data, (address))` call in the source will revert on too-short data, but this is an edge case worth documenting. Since `abi.decode` behavior is well-defined and the `initializer` modifier ensures the proxy remains re-initializable after a failed decode, this is informational only.

### A05-5 — INFO: Double-init test only tries same asset, not a different one

**File:** `test/src/concrete/StoxWrappedTokenVault.t.sol`

`testDoubleInitializeReverts` (line 86) re-initializes with the same asset address. The previous audit fix (A05-5) proposed an additional variant testing re-initialization with a different asset to confirm the `initializer` modifier (not asset equality) prevents re-init. This variant was not implemented. Since the `initializer` modifier is well-audited OZ code and the existing test is sufficient to catch removal of the modifier, this is informational only.

### A05-6 — INFO: `testInitializeAddressAlwaysReverts` tests on implementation, not proxy

**File:** `test/src/concrete/StoxWrappedTokenVault.t.sol`, line 29

`testInitializeAddressAlwaysReverts` calls `initialize(address)` on the raw implementation contract (`new StoxWrappedTokenVault()`), not on a beacon proxy. Since `initialize(address)` is `pure` and always reverts unconditionally, the behavior is identical on both implementation and proxy. However, for completeness, testing on a proxy would confirm the function selector is not shadowed or intercepted by the proxy layer. This is informational given that `pure` functions cannot be affected by proxy state.
