# Pass 2: Test Coverage — StoxWrappedTokenVaultBeaconSetDeployer.sol

## Evidence of Thorough Reading

### Source file: `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` (87 lines)

**Contract:** `StoxWrappedTokenVaultBeaconSetDeployer` — line 44

**Functions:**
- `constructor(StoxWrappedTokenVaultBeaconSetDeployerConfig memory config)` — line 55
- `newStoxWrappedTokenVault(address asset) external returns (StoxWrappedTokenVault)` — line 71

**Structs:**
- `StoxWrappedTokenVaultBeaconSetDeployerConfig` — line 31 (fields: `initialOwner`, `initialStoxWrappedTokenVaultImplementation`)

**Events:**
- `Deployment(address sender, address stoxWrappedTokenVault)` — line 49

**Errors:**
- `ZeroVaultImplementation()` — line 13
- `ZeroBeaconOwner()` — line 17
- `InitializeVaultFailed()` — line 20
- `ZeroVaultAsset()` — line 23

**State variables:**
- `iStoxWrappedTokenVaultBeacon` — `IBeacon public immutable` — line 52

---

### Test file: `test/src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.t.sol` (86 lines)

**Contract:** `StoxWrappedTokenVaultBeaconSetDeployerTest is Test` — line 15

**Test functions:**
- `testConstructZeroVaultImplementation(address initialOwner)` — line 18 (fuzz)
- `testConstructZeroBeaconOwner()` — line 30
- `testConstructSuccess(address initialOwner)` — line 42 (fuzz)
- `testNewVaultZeroAsset(address initialOwner)` — line 56 (fuzz)
- `testNewVaultSuccess(address initialOwner)` — line 71 (fuzz)

**Imports used:** `ZeroVaultImplementation`, `ZeroBeaconOwner`, `ZeroVaultAsset` (but NOT `InitializeVaultFailed`)

---

### Additional coverage found via grep

- `test/src/concrete/StoxWrappedTokenVault.t.sol` — uses `StoxWrappedTokenVaultBeaconSetDeployer` as a helper to deploy vaults in tests. Does not add new constructor or `newStoxWrappedTokenVault` path coverage.
- `test/src/concrete/deploy/StoxUnifiedDeployer.t.sol` — uses `StoxWrappedTokenVaultBeaconSetDeployer` indirectly via mock/etch. Does not cover paths directly.
- `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` — fork test, checks deployed codehash. Does not cover error paths.
- `test/src/concrete/StoxWrappedTokenVaultV1.prod.base.t.sol` — fork test for V1 behaviour; includes a `Deployment` event ordering test but against the V1 on-chain deployment, not the V2 contract under review.

---

## Coverage Analysis

### Constructor

| Path | Tested? | Test |
|---|---|---|
| `ZeroVaultImplementation` when impl is zero | YES | `testConstructZeroVaultImplementation` (fuzz) |
| `ZeroBeaconOwner` when owner is zero | YES | `testConstructZeroBeaconOwner` |
| Happy path — beacon created with correct implementation | YES | `testConstructSuccess` (fuzz, asserts `iStoxWrappedTokenVaultBeacon().implementation()`) |

### `newStoxWrappedTokenVault`

| Path | Tested? | Test |
|---|---|---|
| `ZeroVaultAsset` when asset is zero | YES | `testNewVaultZeroAsset` (fuzz) |
| Happy path — vault deployed, correct asset | YES | `testNewVaultSuccess` (fuzz) |
| `InitializeVaultFailed` when initialize returns wrong value | NO | No test anywhere |
| `Deployment` event emitted (asserted with `vm.expectEmit`) | NO | `testNewVaultSuccess` has comment "emits Deployment" but no `vm.expectEmit` assertion |

---

## Findings

### A07-P2-4: `InitializeVaultFailed` error path has no test coverage [LOW]

**Location:** `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol` line 50–52

`InitializeVaultFailed` is imported in the test file's context but never imported in the test file itself (it is not in the import list at line 9–12 of the test file). No test anywhere exercises the branch where `stoxWrappedTokenVault.initialize(abi.encode(asset)) != ICLONEABLE_V2_SUCCESS`.

The path is reachable when the beacon's implementation is replaced with a contract that returns a value other than `ICLONEABLE_V2_SUCCESS`. With the current real `StoxWrappedTokenVault` implementation this branch cannot be triggered without a mock or a custom beacon implementation. Testing it requires deploying a mock implementation that returns a bad value.

**Severity:** LOW

---

### A07-P2-5: `Deployment` event not asserted in happy-path test [LOW]

**Location:** `test/src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.t.sol` line 71–85

`testNewVaultSuccess` has a NatSpec comment "emits Deployment" but contains no `vm.expectEmit` call. The event emission is never asserted in the unit test suite. A regression that removed the `emit Deployment(...)` call would pass all unit tests.

Note: The V1 fork test `testProdV1DeploymentEventAfterInitialize` does verify V1's `Deployment` event ordering against on-chain state, but it tests a different (V1) contract deployment. The V2 unit test suite has no event assertion.

**Severity:** LOW
