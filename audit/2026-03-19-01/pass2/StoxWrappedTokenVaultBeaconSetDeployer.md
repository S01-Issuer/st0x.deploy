# Pass 2: Test Coverage — StoxWrappedTokenVaultBeaconSetDeployer.sol

**Agent:** A09
**File:** `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol`

## Evidence of Thorough Reading

### Source file: `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` (55 lines)

**Errors (file-level):**
- `InitializeVaultFailed()` — line 11
- `ZeroVaultAsset()` — line 14

**Contract:** `StoxWrappedTokenVaultBeaconSetDeployer` — line 25

**Events:**
- `Deployment(address sender, address stoxWrappedTokenVault)` — line 30 (non-indexed parameters)

**Functions:**
- `newStoxWrappedTokenVault(address asset) external returns (StoxWrappedTokenVault)` — line 39

**No constructor.** No state variables. No assembly. No `receive`/`fallback`. Entirely stateless.

**Imports:**
- `BeaconProxy` from OpenZeppelin (line 5)
- `StoxWrappedTokenVault` from `../StoxWrappedTokenVault.sol` (line 6)
- `ICLONEABLE_V2_SUCCESS` from `rain.factory/interface/ICloneableV2.sol` (line 7)
- `LibProdDeployV2` from `../../lib/LibProdDeployV2.sol` (line 8)

**Logic paths in `newStoxWrappedTokenVault`:**
1. Line 40-42: Revert `ZeroVaultAsset()` if `asset == address(0)`
2. Line 44-45: Create `BeaconProxy` with `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON` and empty data
3. Line 47: Emit `Deployment(msg.sender, address(stoxWrappedTokenVault))`
4. Line 49-51: Call `stoxWrappedTokenVault.initialize(abi.encode(asset))`, revert `InitializeVaultFailed()` if return != `ICLONEABLE_V2_SUCCESS`
5. Line 53: Return the vault

---

### Test file: `test/src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.t.sol` (69 lines)

**Contract:** `StoxWrappedTokenVaultBeaconSetDeployerTest is Test` — line 20

**Test functions:**
- `testNewVaultZeroAsset()` — line 23: Tests `ZeroVaultAsset` revert when `asset == address(0)`
- `testNewVaultSuccess()` — line 32: Happy-path test; checks vault address non-zero, `vault.asset()` correct, `Deployment` event emitted with correct parameters via `vm.recordLogs()`
- `testNewVaultInitializeVaultFailed()` — line 59: Tests `InitializeVaultFailed` revert by upgrading beacon to `BadInitializeVault` implementation

**Imports:**
- `ZeroVaultAsset`, `InitializeVaultFailed` from source (lines 8-9)
- `StoxWrappedTokenVault` (line 11)
- `StoxWrappedTokenVaultBeacon` (line 12)
- `LibRainDeploy` (line 13)
- `MockERC20` (line 14)
- `BadInitializeVault` (line 15)
- `LibTestDeploy` (line 16)
- `LibProdDeployV2` (line 17)
- `UpgradeableBeacon` (line 18)

---

### Helper file: `test/concrete/BadInitializeVault.sol` (11 lines)

**Contract:** `BadInitializeVault` — line 7

**Functions:**
- `initialize(bytes calldata) external pure returns (bytes32)` — line 8: Returns `bytes32(0)` instead of `ICLONEABLE_V2_SUCCESS`

---

### Additional test coverage from other files

Searched all test files referencing `StoxWrappedTokenVaultBeaconSetDeployer`, `newStoxWrappedTokenVault`, `InitializeVaultFailed`, `ZeroVaultAsset`, and `Deployment(`:

- **`test/src/concrete/StoxWrappedTokenVaultV2.t.sol`** — `testV2ZeroAssetReverts()` (line 20): duplicate ZeroVaultAsset test; `testV2DeploymentEventBeforeInitialize()` (line 29): verifies Deployment event ordering relative to init event via `vm.recordLogs()`; `testV2NewVaultSuccess()` (line 63): validates `asset()`, `name()`, `symbol()` delegation
- **`test/src/concrete/StoxWrappedTokenVault.t.sol`** — exercises `newStoxWrappedTokenVault` extensively as a setup step for vault behavior tests; does not directly test deployer error paths
- **`test/src/concrete/deploy/StoxUnifiedDeployer.t.sol`** — exercises `ZeroVaultAsset` via the unified deployer path (line 103-106)
- **`test/src/concrete/deploy/StoxProdV2.t.sol`** — fork tests verifying deployer codehash on-chain across 5 networks (lines 34-39)
- **`test/src/concrete/StoxWrappedTokenVaultV1.prod.base.t.sol`** — V1 fork test, verifies V1 `Deployment` event ordering; not relevant to V2 deployer

---

## Coverage Analysis

### `newStoxWrappedTokenVault` — all logic paths

| # | Path | Tested? | Test(s) |
|---|------|---------|---------|
| 1 | `ZeroVaultAsset` revert when `asset == address(0)` | YES | `testNewVaultZeroAsset` (deployer test), `testV2ZeroAssetReverts` (V2 test) |
| 2 | `BeaconProxy` creation with correct beacon address | YES | `testNewVaultSuccess` (deployer test), `testV2NewVaultSuccess` (V2 test) |
| 3 | `Deployment` event emitted with correct `sender` and `stoxWrappedTokenVault` | YES | `testNewVaultSuccess` (deployer test, lines 38-54 via `vm.recordLogs()`) |
| 4 | `Deployment` event emitted before `initialize` call (CEI) | YES | `testV2DeploymentEventBeforeInitialize` (V2 test, lines 29-58) |
| 5 | `InitializeVaultFailed` revert when initialize returns wrong value | YES | `testNewVaultInitializeVaultFailed` (deployer test, lines 59-68) |
| 6 | Happy path: vault returned with correct `asset()` | YES | `testNewVaultSuccess` (deployer test), `testV2NewVaultSuccess` (V2 test) |
| 7 | Vault `name()` and `symbol()` delegation through proxy | YES | `testV2NewVaultSuccess` (V2 test, lines 71-72) |
| 8 | On-chain codehash of deployer matches constant | YES | `StoxProdV2Test` fork tests across 5 networks |

### Edge cases and implicit paths

| # | Scenario | Tested? | Notes |
|---|----------|---------|-------|
| E1 | Beacon not deployed at expected address | NO | If `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON` has no code, `new BeaconProxy(...)` reverts inside OZ constructor. Not a custom error from this contract. |
| E2 | Re-initialization of returned vault (double-init) | INDIRECT | Covered by `StoxWrappedTokenVault` tests using `initializer` modifier, not specific to deployer |
| E3 | Multiple sequential deployments from same deployer | NO | No test calls `newStoxWrappedTokenVault` twice in succession to verify independent proxies |

---

## Findings

### A09-1: No test for multiple sequential deployments from the same deployer instance [INFO]

**Location:** `test/src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.t.sol`

No test calls `newStoxWrappedTokenVault` more than once per test case to verify that sequential deployments produce independent, correctly-initialized proxies. The contract is stateless so this is architecturally guaranteed, but a test would serve as a regression guard if state were ever accidentally introduced.

**Severity:** INFO -- The contract has zero mutable state, making sequential deployment independence a structural invariant. The risk of regression is negligible.

---

### Summary

The test coverage for `StoxWrappedTokenVaultBeaconSetDeployer` is thorough. All three previous audit findings from 2026-03-18-01 (A07-P2-4: `InitializeVaultFailed` not tested, A07-P2-5: `Deployment` event not asserted) have been addressed:

- `testNewVaultInitializeVaultFailed` (line 59) covers the `InitializeVaultFailed` error path using `BadInitializeVault` mock
- `testNewVaultSuccess` (line 32) asserts `Deployment` event parameters via `vm.recordLogs()`
- `testV2DeploymentEventBeforeInitialize` in the V2 test file additionally verifies event ordering (CEI)

Every reachable branch in the source contract has at least one corresponding test. No LOW or above findings identified.
