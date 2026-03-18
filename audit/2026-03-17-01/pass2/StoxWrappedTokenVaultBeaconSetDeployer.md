# Pass 2: Test Coverage — A06: StoxWrappedTokenVaultBeaconSetDeployer.sol

## Evidence of Thorough Reading

**File:** `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` (87 lines)

**Contract:** `StoxWrappedTokenVaultBeaconSetDeployer` (line 44)

**Struct:** `StoxWrappedTokenVaultBeaconSetDeployerConfig` (lines 31-34)

**Functions:**
| Function | Line | Visibility |
|---|---|---|
| `constructor(StoxWrappedTokenVaultBeaconSetDeployerConfig)` | 55 | N/A |
| `newStoxWrappedTokenVault(address)` | 71 | `external` |

**Custom Errors:** `ZeroVaultImplementation` (13), `ZeroBeaconOwner` (17), `InitializeVaultFailed` (20), `ZeroVaultAsset` (23)

**Event:** `Deployment(address sender, address stoxWrappedTokenVault)` (line 49)

**State:** `I_STOX_WRAPPED_TOKEN_VAULT_BEACON` (line 52), `IBeacon public immutable`

## Test Search

No dedicated test file exists. The only reference in tests is `StoxUnifiedDeployer.t.sol`, which completely mocks `newStoxWrappedTokenVault` via `vm.mockCall` — zero real logic exercised.

The analogous ethgild contract has tests at `lib/ethgild/test/src/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.construct.t.sol`. No equivalent exists here.

## Findings

### A06-2: No test coverage for StoxWrappedTokenVaultBeaconSetDeployer [LOW]

All six code paths are untested:
1. Constructor revert on zero implementation (`ZeroVaultImplementation`)
2. Constructor revert on zero owner (`ZeroBeaconOwner`)
3. Constructor success (beacon creation + immutable assignment)
4. `newStoxWrappedTokenVault` revert on zero asset (`ZeroVaultAsset`)
5. `newStoxWrappedTokenVault` revert on failed init (`InitializeVaultFailed`)
6. `newStoxWrappedTokenVault` success (proxy creation, initialization, event, return value)

See `.fixes/A06-2.md` for proposed test file.
