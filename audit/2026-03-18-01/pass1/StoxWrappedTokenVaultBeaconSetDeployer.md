# Pass 1: Security — StoxWrappedTokenVaultBeaconSetDeployer.sol

## Evidence of Thorough Reading

**File:** `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` (87 lines)

**Contract:** `StoxWrappedTokenVaultBeaconSetDeployer` (line 44)

**Functions:**
- `constructor(StoxWrappedTokenVaultBeaconSetDeployerConfig memory config)` — line 55
- `newStoxWrappedTokenVault(address asset)` — line 71

**Structs defined:**
- `StoxWrappedTokenVaultBeaconSetDeployerConfig` — line 31 (fields: `initialOwner`, `initialStoxWrappedTokenVaultImplementation`)

**Events defined:**
- `Deployment(address sender, address stoxWrappedTokenVault)` — line 49

**Errors defined:**
- `ZeroVaultImplementation()` — line 13
- `ZeroBeaconOwner()` — line 17
- `InitializeVaultFailed()` — line 20
- `ZeroVaultAsset()` — line 23

**State variables:**
- `iStoxWrappedTokenVaultBeacon` — `IBeacon public immutable` — line 52

**Imports:** `IBeacon`, `UpgradeableBeacon`, `BeaconProxy` (OpenZeppelin), `StoxWrappedTokenVault`, `ICLONEABLE_V2_SUCCESS`

**No assembly blocks. No string reverts. All reverts use custom errors.**

## Findings

### A07-3: `Deployment` event emitted before vault initialization is confirmed [LOW]

In `newStoxWrappedTokenVault`, the `Deployment` event is emitted at line 79 before `stoxWrappedTokenVault.initialize(...)` is called and its return value checked at lines 81–83.

The event's NatSpec states "Emitted when a new deployment is **successfully initialized**", but at the point of emission the vault has not yet been initialized. If `initialize` returned a non-success value (triggering `revert InitializeVaultFailed()`), the event would be reverted by the EVM and never appear in the final receipt — so it cannot be observed externally in a failure case. However, the semantic contract implied by the NatSpec is violated: the event fires before success is confirmed.

The upstream contract this is modelled on (`OffchainAssetReceiptVaultBeaconSetDeployer`, ethgild) emits its `Deployment` event only after both initializations succeed (line 97 of that file). This ordering is the established pattern in the codebase.

The practical risk is low because:
1. A revert rolls back the event, so it is only visible post-transaction on success.
2. This contract is stateless, so reentrancy during `initialize` cannot exploit mutated state.

However, the incorrect ordering is a deviation from the documented pattern, violates the event's own NatSpec, and could mislead off-chain listeners or auditors reading the code.

**Severity:** LOW

**Location:** `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol`, lines 79 and 81–83

**Recommendation:** Move `emit Deployment(...)` to after the `initialize` check, consistent with the upstream contract.
