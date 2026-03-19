# Pass 1: Security — StoxWrappedTokenVaultBeaconSetDeployer.sol

**Agent:** A09
**File:** `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol`

## Evidence of Thorough Reading

**Contract:** `StoxWrappedTokenVaultBeaconSetDeployer` (line 25)

**Functions:**
- `newStoxWrappedTokenVault(address asset) external returns (StoxWrappedTokenVault)` — line 39

**Events defined:**
- `Deployment(address sender, address stoxWrappedTokenVault)` — line 30

**Errors defined (file-level):**
- `InitializeVaultFailed()` — line 11
- `ZeroVaultAsset()` — line 14

**Constants/State variables:** None. The contract is entirely stateless.

**Imports:**
- `BeaconProxy` from OpenZeppelin (line 5)
- `StoxWrappedTokenVault` from `../StoxWrappedTokenVault.sol` (line 6)
- `ICLONEABLE_V2_SUCCESS` from `rain.factory/interface/ICloneableV2.sol` (line 7)
- `LibProdDeployV2` from `../../lib/LibProdDeployV2.sol` (line 8)

**No constructor.** No assembly blocks. No string reverts. All reverts use custom errors. No `receive`/`fallback`. No mutable state.

## Security Analysis

### Reentrancy
The contract has no mutable state. Two external calls exist: `new BeaconProxy(...)` (line 45) and `stoxWrappedTokenVault.initialize(...)` (line 49). Neither can exploit reentrancy because there is no state to corrupt. The `initializer` modifier on `StoxWrappedTokenVault.initialize(bytes)` prevents double-initialization. The `slither-disable-next-line reentrancy-events` at line 38 is justified by the `@dev` NatSpec at lines 33-34.

### Event ordering (CEI)
The `Deployment` event is emitted at line 47 before the `initialize` call at line 49. This was an intentional change documented in the CHANGELOG ("Moved `Deployment` event emit before `initialize` call (checks-effects-interactions)") and was dismissed as a false positive in the 2026-03-18-01 triage (A07-3). Not re-flagged.

### Input validation
- Zero address check on `asset` at line 40. Correct.
- Return value of `initialize` checked against `ICLONEABLE_V2_SUCCESS` at line 49. Correct.

### Access control
`newStoxWrappedTokenVault` is permissionless (`external`, no modifier). This is by design — it is a factory function.

### Front-running
The `BeaconProxy` is created and initialized atomically within a single transaction. The `initializer` modifier on the vault prevents anyone from front-running the initialization between creation and the `initialize` call.

### Beacon dependency
The beacon address is a compile-time constant from `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON`. If the beacon is not deployed at that address, the `BeaconProxy` constructor will revert. This is expected and correct behavior.

## Findings

No security findings at LOW or above. The contract is minimal, stateless, validates inputs, checks return values, uses custom errors, and follows CEI ordering.
