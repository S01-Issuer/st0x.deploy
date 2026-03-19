# Pass 2 (Test Coverage) - StoxWrappedTokenVaultBeacon.sol

**Agent:** A06
**File:** `src/concrete/StoxWrappedTokenVaultBeacon.sol`
**Test file:** `test/src/concrete/StoxWrappedTokenVaultBeacon.t.sol`

## Evidence of Thorough Reading -- Source File

**Contract name:** `StoxWrappedTokenVaultBeacon` (line 11)

**Imports:**
- `UpgradeableBeacon` from `openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol` (line 5)
- `LibProdDeployV2` from `../lib/LibProdDeployV2.sol` (line 6)

**Contract body:** Empty (`{}`, line 13). All behavior is inherited.

**Constructor (inline inheritance specifier, line 12):**
- Passes `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT` as `implementation_`
- Passes `LibProdDeployV2.BEACON_INITIAL_OWNER` as `initialOwner`

**Inherited public/external functions (from UpgradeableBeacon + Ownable):**
- `implementation()` -- view, returns current implementation address (UpgradeableBeacon line 38)
- `upgradeTo(address)` -- onlyOwner, sets new implementation (UpgradeableBeacon line 52)
- `owner()` -- view, returns current owner (Ownable)
- `transferOwnership(address)` -- onlyOwner, transfers ownership (Ownable)
- `renounceOwnership()` -- onlyOwner, sets owner to address(0) (Ownable)

**Inherited errors:**
- `BeaconInvalidImplementation(address)` (UpgradeableBeacon line 21)
- `OwnableUnauthorizedAccount(address)` (Ownable)
- `OwnableInvalidOwner(address)` (Ownable)

**Inherited events:**
- `Upgraded(address indexed implementation)` (UpgradeableBeacon line 26)
- `OwnershipTransferred(address indexed previousOwner, address indexed newOwner)` (Ownable)

**Types/constants defined in this file:** None.

## Evidence of Thorough Reading -- Test File

**Contract name:** `StoxWrappedTokenVaultBeaconTest` (line 13)

**Imports:**
- `Test` from `forge-std/Test.sol` (line 4)
- `LibRainDeploy` from `rain.deploy/lib/LibRainDeploy.sol` (line 6)
- `StoxWrappedTokenVault` from `../../../src/concrete/StoxWrappedTokenVault.sol` (line 7)
- `StoxWrappedTokenVaultBeacon` from `../../../src/concrete/StoxWrappedTokenVaultBeacon.sol` (line 8)
- `LibProdDeployV1` from `../../../src/lib/LibProdDeployV1.sol` (line 9)
- `LibProdDeployV2` from `../../../src/lib/LibProdDeployV2.sol` (line 10)
- `Ownable` from `openzeppelin-contracts/contracts/access/Ownable.sol` (line 11)

**Test functions:**
- `testBeaconConstructsWithExpectedConstants()` (line 15) -- Deploys via Zoltu, asserts deterministic address matches `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON`, asserts `implementation()` and `owner()` match expected constants.
- `testBeaconInitialOwnerConsistentAcrossVersions()` (line 26) -- Pure assertion that `LibProdDeployV1.BEACON_INITIAL_OWNER == LibProdDeployV2.BEACON_INITIAL_OWNER`.

**Types/errors/constants defined in test file:** None.

## Coverage Analysis

### What IS covered:

1. **Constructor correctness** -- `testBeaconConstructsWithExpectedConstants` verifies the beacon deploys at the expected Zoltu address with the correct implementation and owner. This covers the only first-party code (the constructor arguments).
2. **Version consistency** -- `testBeaconInitialOwnerConsistentAcrossVersions` verifies the owner constant is the same across V1 and V2.
3. **`upgradeTo` (indirect)** -- `StoxWrappedTokenVaultBeaconSetDeployer.t.sol` line 63 calls `upgradeTo` from the owner, confirming it works. However, this is not a dedicated beacon test.

### What is NOT covered:

1. **`upgradeTo` access control** -- No test verifies that a non-owner cannot call `upgradeTo`.
2. **`upgradeTo` with invalid implementation** -- No test verifies that `upgradeTo` reverts when called with an address that has no code (`BeaconInvalidImplementation`).
3. **`transferOwnership` behavior** -- No test verifies the owner can transfer ownership, or that a non-owner cannot.
4. **`renounceOwnership` behavior** -- No test verifies `renounceOwnership` exists and can be called (or documents that it should not be callable). This is the behavior flagged in Pass 1 finding A06-1.
5. **`renounceOwnership` consequences** -- No test demonstrates that after `renounceOwnership`, `upgradeTo` permanently fails. This would document the risk flagged in A06-1.
6. **Event emission** -- No test verifies that the constructor emits `Upgraded` and `OwnershipTransferred` events.

## Findings

### A06-P2-1: No test coverage for ownership-gated functions on the beacon [LOW]

**Location:** `test/src/concrete/StoxWrappedTokenVaultBeacon.t.sol`

**Description:** The test file only covers constructor constants and version consistency. The beacon's primary operational functions -- `upgradeTo`, `transferOwnership`, and `renounceOwnership` -- have no dedicated test coverage. While `upgradeTo` is exercised indirectly in `StoxWrappedTokenVaultBeaconSetDeployer.t.sol` (line 63), there are no tests for:

- Non-owner calling `upgradeTo` should revert with `OwnableUnauthorizedAccount`.
- Non-owner calling `transferOwnership` should revert with `OwnableUnauthorizedAccount`.
- Owner calling `transferOwnership` should succeed and change the owner.
- `upgradeTo` with an EOA (no code) should revert with `BeaconInvalidImplementation`.

These are OpenZeppelin-inherited behaviors, so the risk is mitigated by OZ's own test suite. However, testing access control on your own deployed instance confirms the constructor correctly wired the owner, and guards against future regressions if the contract is modified (e.g., if A06-1's fix is applied).

**Severity rationale:** LOW because the untested functions are standard OpenZeppelin code with well-established correctness, and the constructor arguments are already verified to be correct. The gap is primarily a documentation/regression-safety concern.

### A06-P2-2: No test demonstrating `renounceOwnership` permanently disables upgrades [INFO]

**Location:** `test/src/concrete/StoxWrappedTokenVaultBeacon.t.sol`

**Description:** Pass 1 finding A06-1 flagged that `renounceOwnership()` can permanently lock out beacon upgrades. There is no test that demonstrates this behavior -- i.e., calling `renounceOwnership()` as the owner, then verifying that `upgradeTo` reverts with `OwnableUnauthorizedAccount(address(0))`.

Such a test would serve as living documentation of the risk and would also validate any future fix (e.g., if A06-1's proposed override is applied, the test would need to expect `RenounceOwnershipDisabled` instead).

This is informational since it documents a risk that is already captured in A06-1, and the behavior is well-understood from OpenZeppelin's Ownable contract.
