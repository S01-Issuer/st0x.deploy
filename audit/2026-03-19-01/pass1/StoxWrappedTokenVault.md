# Pass 1: Security — StoxWrappedTokenVault.sol

## Evidence of Thorough Reading

**File:** `src/concrete/StoxWrappedTokenVault.sol` (71 lines)

**Contract:** `StoxWrappedTokenVault` (line 29) — inherits `ERC4626Upgradeable`, `ICloneableV2`

**Functions:**

| Function | Line | Visibility | Modifiers |
|---|---|---|---|
| `constructor()` | 36 | implicit public | — |
| `initialize(address asset)` | 43 | `external pure` | — |
| `initialize(bytes calldata data)` | 51 | `external` | `initializer` |
| `name()` | 63 | `public view` | `override(IERC20Metadata, ERC20Upgradeable)` |
| `symbol()` | 68 | `public view` | `override(IERC20Metadata, ERC20Upgradeable)` |

**Events:**
- `StoxWrappedTokenVaultInitialized(address indexed sender, address indexed asset)` (line 33)

**Errors (file scope):**
- `ZeroAsset()` (line 13)

**Errors (inherited):**
- `InitializeSignatureFn()` (from `ICloneableV2`) — used at line 45

**Constants/imports:**
- `ICLONEABLE_V2_SUCCESS` (from `rain.factory/interface/ICloneableV2.sol`) — line 9
- `ERC4626Upgradeable` (from OpenZeppelin Upgradeable) — line 6-7
- `ERC20Upgradeable` (from OpenZeppelin Upgradeable) — line 8
- `ICloneableV2` (from `rain.factory`) — line 9
- `IERC20Metadata` (from OpenZeppelin) — line 10

## Security Checklist

1. **Constructor `_disableInitializers()`** (line 37) — PASS. Prevents direct initialization of the bare implementation contract.
2. **`initialize(address)` always reverts** (line 43-46) — PASS. Unconditionally reverts with `InitializeSignatureFn()`, satisfying ICloneableV2 documentation-overload requirement. The `(asset);` statement on line 44 suppresses the unused parameter warning without side effects.
3. **`initialize(bytes)` uses `initializer` modifier** (line 51) — PASS. OpenZeppelin's `Initializable` guard prevents re-initialization.
4. **Zero-address validation** (line 53) — PASS. `if (asset == address(0)) revert ZeroAsset()` prevents initialization with a null asset.
5. **Initialization order** (lines 54-55) — PASS. `__ERC4626_init` is called first (sets the asset and decimals in ERC4626 storage), then `__ERC20_init("", "")` (sets empty name/symbol in ERC20 storage). The order is correct: `__ERC4626_init` does not depend on ERC20 state. The empty strings passed to `__ERC20_init` are intentional since `name()` and `symbol()` are overridden to derive dynamically from the asset.
6. **Reentrancy** — PASS. This file defines no state-mutating functions that make external calls. The `name()` and `symbol()` view functions call into the asset via `STATICCALL`, preventing reentrancy. Inherited ERC4626 deposit/withdraw use the correct transfer-before-mint / burn-before-transfer patterns.
7. **Arithmetic** — PASS. No arithmetic in this contract's own code. Inherited ERC4626 math (mulDiv with rounding) is in `ERC4626Upgradeable`.
8. **Rounding direction (inherited ERC4626)** — PASS. The inherited `ERC4626Upgradeable` applies correct directional rounding per the General Rules: `deposit`/`convertToShares` floor (fewer shares minted, favors vault/protocol), `previewMint`/`previewWithdraw` ceil (more assets charged/shares burned, favors vault/protocol), `redeem`/`convertToAssets` floor (fewer assets returned, favors vault/protocol). No overrides in this contract alter rounding.
9. **Custom errors only** — PASS. Both error paths use custom errors (`ZeroAsset`, `InitializeSignatureFn`). No string reverts.
10. **No assembly** — PASS. No inline assembly in this file.
11. **Access control** — PASS. No privileged state-mutating functions beyond `initialize`, which is guarded by the `initializer` modifier (one-time initialization only).
12. **ICloneableV2 compliance** — PASS. `initialize(bytes)` returns `ICLONEABLE_V2_SUCCESS` on line 59; `initialize(address)` always reverts; constructor calls `_disableInitializers()`.
13. **ERC4626 inflation attack** — PASS. OpenZeppelin v5 virtual shares/assets mitigation (`totalSupply() + 10 ** _decimalsOffset()` and `totalAssets() + 1`) is present in the inherited base class and not overridden or disabled. `_decimalsOffset()` returns 0 (default), so virtual shares are 1 and virtual assets are 1.
14. **`name()`/`symbol()` external calls** (lines 63-70) — PASS. These call `IERC20Metadata(asset()).name()` and `.symbol()` on the stored asset address set at initialization. The asset is intended to be a `StoxReceiptVault` which implements `IERC20Metadata`. If a non-compliant ERC20 (lacking `name()`/`symbol()`) were used as the asset, these calls would revert — but this is an acceptable design choice since the asset is validated at deployment time and the vault is purpose-built for wrapping receipt vaults.
15. **`abi.decode` safety** (line 52) — PASS. `abi.decode(data, (address))` will revert on malformed input (too short or badly encoded data). This is before the `initializer` state change takes effect, so failed decoding leaves the proxy uninitialized and re-initializable.
16. **Event emission** (line 57) — PASS. `StoxWrappedTokenVaultInitialized` is emitted after state changes, with `_msgSender()` and the validated asset address.

## Findings

No findings. The contract is minimal, well-structured, and delegates security-critical ERC4626 logic to a well-audited OpenZeppelin base. All initialization guards, input validation, rounding directions, and interface compliance checks pass review.
