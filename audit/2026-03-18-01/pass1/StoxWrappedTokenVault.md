# Pass 1: Security — StoxWrappedTokenVault.sol

## Evidence of Thorough Reading

**File:** `src/concrete/StoxWrappedTokenVault.sol` (69 lines)

**Contract:** `StoxWrappedTokenVault` (line 28) — inherits `ERC4626Upgradeable`, `ICloneableV2`

**Functions:**

| Function | Line | Visibility | Modifier |
|---|---|---|---|
| `constructor()` | 34 | implicit public | — |
| `initialize(address asset)` | 41 | `external pure` | — |
| `initialize(bytes calldata data)` | 49 | `external` | `initializer` |
| `name()` | 61 | `public view override` | — |
| `symbol()` | 66 | `public view override` | — |

**Events:**
- `StoxWrappedTokenVaultInitialized(address indexed sender, address indexed asset)` (line 32)

**Errors (file scope):**
- `ZeroAsset()` (line 12)

**Errors (inherited from ICloneableV2):**
- `InitializeSignatureFn()` — used at line 43

**Constants/imports:**
- `ICLONEABLE_V2_SUCCESS` (from `rain.factory/interface/ICloneableV2.sol`)
- `ERC4626Upgradeable`, `ERC20Upgradeable` (OpenZeppelin Upgradeable)
- `IERC20Metadata` (OpenZeppelin)

## Security Checklist

1. **Constructor `_disableInitializers()`** — PASS. Prevents initialization of the bare implementation contract.
2. **`initialize(address)` always reverts** — PASS. Unconditionally reverts with `InitializeSignatureFn()`, satisfying ICloneableV2 documentation-overload requirement.
3. **`initialize(bytes)` uses `initializer` modifier** — PASS. Prevents re-initialization (OpenZeppelin `Initializable` guard).
4. **Input validation** — PASS. Zero-address check (`if (asset == address(0)) revert ZeroAsset()`) present at line 51, applying after `abi.decode`. This was finding A04-1 in the prior session; the fix has been applied.
5. **Reentrancy** — PASS. `name()` and `symbol()` are `view` functions; external calls execute via `STATICCALL`, making reentrancy impossible. No state-mutating external calls in this file's own functions.
6. **Arithmetic** — PASS. No arithmetic in this file. All ERC4626 math (mulDiv with rounding) is in `ERC4626Upgradeable`.
7. **Rounding direction (ERC4626 base)** — PASS. The inherited `ERC4626Upgradeable` applies correct directional rounding: `previewDeposit` and `convertToShares` floor (favor vault), `previewMint` and `previewWithdraw` ceil (favor vault), `previewRedeem` and `convertToAssets` floor (favor vault). No overrides in this contract alter rounding.
8. **Custom errors only** — PASS. No string reverts. Both error paths (`ZeroAsset`, `InitializeSignatureFn`) are custom errors.
9. **No assembly** — PASS. No inline assembly in this file.
10. **Access control** — PASS. No privileged state-mutating functions exist beyond `initialize`, which is correctly guarded by `initializer`.
11. **ICloneableV2 pattern** — PASS. `initialize(bytes)` returns `ICLONEABLE_V2_SUCCESS`; `initialize(address)` always reverts; constructor calls `_disableInitializers()`.
12. **ERC4626 compliance** — PASS. No overrides to vault deposit/withdraw mechanics; all inherited from OpenZeppelin. `__ERC4626_init` and `__ERC20_init` called in correct order during initialization.
13. **Inflation attack (ERC4626)** — PASS. OpenZeppelin v5 virtual shares mitigation (`totalSupply() + 10 ** _decimalsOffset()` and `totalAssets() + 1` in `_convertToShares`/`_convertToAssets`) is present in the base class and not disabled.
14. **`name()`/`symbol()` external calls** — PASS. `IERC20Metadata(asset()).name()` and `.symbol()` are called on the stored asset address. These are `view` functions; the asset is set once at initialization and cannot be changed. No trust assumption needed beyond the initial deployer choice.

## Findings

No findings.
