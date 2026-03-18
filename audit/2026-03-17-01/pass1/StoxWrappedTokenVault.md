# Pass 1: Security — A04: StoxWrappedTokenVault.sol

## Evidence of Thorough Reading

**File:** `src/concrete/StoxWrappedTokenVault.sol` (63 lines)

**Contract:** `StoxWrappedTokenVault` (line 25) — inherits `ERC4626Upgradeable`, `ICloneableV2`

**Functions:**
| Function | Line | Visibility |
|---|---|---|
| `constructor()` | 31 | implicit (public) |
| `initialize(address)` | 38 | `external pure` |
| `initialize(bytes)` | 44 | `external` (with `initializer` modifier) |
| `name()` | 55 | `public view override` |
| `symbol()` | 60 | `public view override` |

**Event:** `StoxWrappedTokenVaultInitialized(address indexed sender, address indexed asset)` (line 29)

**Errors defined:** None in this file. Uses `InitializeSignatureFn()` from `ICloneableV2`.

## Security Checklist Results

1. **Constructor `_disableInitializers()`** — PASS. Prevents initialization of the implementation contract.
2. **`initialize(address)` always reverts** — PASS. Unconditionally reverts with `InitializeSignatureFn()`.
3. **`initialize(bytes)` uses `initializer` modifier** — PASS. Prevents re-initialization.
4. **Input validation** — See finding A04-1.
5. **Init ordering** — PASS. Independent ERC-7201 storage namespaces, no dependency.
6. **`name()`/`symbol()` external calls** — PASS. Read-only `view` functions; reentrancy impossible via `STATICCALL`.
7. **ERC-4626 compliance** — PASS. No overrides to vault mechanics; all inherited from OpenZeppelin.
8. **Custom errors only** — PASS. No string reverts.

## Findings

### A04-1: No zero-address validation for `asset` in `initialize(bytes)` [LOW]

The `initialize(bytes)` function (line 44) decodes an `asset` address and passes it to `__ERC4626_init` without checking for `address(0)`. The deployer contract (`StoxWrappedTokenVaultBeaconSetDeployer`) does validate this, but `ICloneableV2` specifies cloneables "MUST NOT assume" factory deployment. A direct call with `address(0)` would brick the vault permanently (no funds at risk, just a dead proxy).

**Proposed fix:** Add `if (asset == address(0)) revert ZeroAsset();` after decoding, with a custom error defined at file scope. See `.fixes/A04-1.md`.
