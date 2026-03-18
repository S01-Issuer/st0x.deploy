# Pass 1: Security — A06: StoxWrappedTokenVaultBeaconSetDeployer.sol

## Evidence of Thorough Reading

**File:** `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` (87 lines)

**Contract:** `StoxWrappedTokenVaultBeaconSetDeployer` (line 44), no inheritance.

**Functions:**
| Function | Line | Visibility |
|---|---|---|
| `constructor(StoxWrappedTokenVaultBeaconSetDeployerConfig)` | 55 | N/A (constructor) |
| `newStoxWrappedTokenVault(address)` | 71 | `external` |

**Custom Errors (file-level):**
| Error | Line |
|---|---|
| `ZeroVaultImplementation()` | 13 |
| `ZeroBeaconOwner()` | 17 |
| `InitializeVaultFailed()` | 20 |
| `ZeroVaultAsset()` | 23 |

**Events:** `Deployment(address sender, address stoxWrappedTokenVault)` at line 49.

**Structs:** `StoxWrappedTokenVaultBeaconSetDeployerConfig` (lines 31-34), fields: `address initialOwner`, `address initialStoxWrappedTokenVaultImplementation`.

**State Variables:** `I_STOX_WRAPPED_TOKEN_VAULT_BEACON` (line 52), `IBeacon public immutable`.

### Security Checklist Results

- **Input validation:** All three inputs (implementation address, owner, asset) are checked against zero address. Adequate.
- **Access controls:** `newStoxWrappedTokenVault` is permissionless. Intentional and safe — each call creates an independent proxy with no shared mutable state.
- **Reentrancy:** No risk. No shared mutable state between invocations. The `initializer` modifier prevents double-initialization.
- **Initialize return value:** Correctly validated against `ICLONEABLE_V2_SUCCESS` (line 79), reverts with `InitializeVaultFailed()` on mismatch.
- **Beacon pattern:** `UpgradeableBeacon` created in constructor, stored as `immutable`. Correct.
- **Custom errors only:** All error paths use custom errors. No string reverts.
- **Frontrunning between creation and initialization:** Not exploitable. Both `new BeaconProxy(...)` and `initialize(...)` occur within the same transaction. The `initializer` modifier prevents double-initialization regardless.

## Findings

### A06-1: Duplicate error definitions with ethgild's ErrDeployer.sol [INFO]

Three errors (`ZeroVaultImplementation`, `ZeroBeaconOwner`, `InitializeVaultFailed`) are duplicated from `lib/ethgild/src/error/ErrDeployer.sol`. No security impact (identical selectors), but a maintenance observation.
