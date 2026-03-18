# Pass 2: Test Coverage — A04: StoxWrappedTokenVault.sol

## Evidence of Thorough Reading

**File:** `src/concrete/StoxWrappedTokenVault.sol` (63 lines)

**Contract:** `StoxWrappedTokenVault` (line 25) — inherits `ERC4626Upgradeable`, `ICloneableV2`

**Functions:**
| Function | Line | Visibility |
|---|---|---|
| `constructor()` | 31 | implicit |
| `initialize(address)` | 38 | `external pure` |
| `initialize(bytes)` | 44 | `external` |
| `name()` | 55 | `public view override` |
| `symbol()` | 60 | `public view override` |

**Event:** `StoxWrappedTokenVaultInitialized(address indexed sender, address indexed asset)` (line 29)

## Test Search

Grepped `test/` for `StoxWrappedTokenVault` — only referenced in `StoxUnifiedDeployer.t.sol` which uses `vm.mockCall` to mock the beacon-set deployer. No real vault instance is ever created or tested.

## Findings

### A04-2: StoxWrappedTokenVault has zero unit-test coverage [LOW]

Every function has zero test coverage. The contract has 5 functions, one event, and full ERC4626 inheritance — none exercised by any test. Untested paths:

1. Constructor `_disableInitializers()` guard
2. `initialize(address)` always-revert behavior
3. `initialize(bytes)` happy path (init, event emission, return value)
4. Re-initialization guard (calling initialize twice)
5. `name()` delegation to underlying asset
6. `symbol()` delegation to underlying asset
7. ERC4626 deposit/withdraw round-trip
8. Zero-address asset in `initialize(bytes)` (relates to A04-1)

See `.fixes/A04-2.md` for proposed test file.
