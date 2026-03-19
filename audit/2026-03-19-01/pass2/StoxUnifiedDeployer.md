# Pass 2: Test Coverage -- StoxUnifiedDeployer.sol

**Agent:** A08
**File:** `src/concrete/deploy/StoxUnifiedDeployer.sol`

## Evidence of Thorough Reading

### Source file: `src/concrete/deploy/StoxUnifiedDeployer.sol` (45 lines)

**Contract:** `StoxUnifiedDeployer` (line 19)
- No constructor
- No state variables
- No inheritance
- No custom errors defined in this file
- No types defined in this file

**Events:**

| Line | Name | Parameters |
|------|------|------------|
| 25 | `Deployment` | `address sender`, `address asset`, `address wrapper` (none indexed) |

**Functions:**

| Line | Name | Visibility | Mutability |
|------|------|------------|------------|
| 35 | `newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config)` | `external` | state-changing |

**Imports (lines 5-12):**
- `OffchainAssetReceiptVaultBeaconSetDeployer`, `OffchainAssetReceiptVaultConfigV2`, `OffchainAssetReceiptVault` from `ethgild/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol`
- `StoxWrappedTokenVaultBeaconSetDeployer` from `./StoxWrappedTokenVaultBeaconSetDeployer.sol`
- `LibProdDeployV2` from `../../lib/LibProdDeployV2.sol`
- `StoxWrappedTokenVault` from `../StoxWrappedTokenVault.sol`

**Constants used (imported from `LibProdDeployV2`):**
- `LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` -- Zoltu deterministic address (line 37)
- `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` -- Zoltu deterministic address (line 40)

**Slither suppression:** `reentrancy-events` at line 34 with `@dev` comment (lines 29-31) explaining the contract is entirely stateless.

**Logic paths in `newTokenAndWrapperVault`:**
1. Line 36-38: Cast `LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` to `OffchainAssetReceiptVaultBeaconSetDeployer` and call `newOffchainAssetReceiptVault(config)`, store result as `asset`.
2. Line 39-41: Cast `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` to `StoxWrappedTokenVaultBeaconSetDeployer` and call `newStoxWrappedTokenVault(address(asset))`, store result as `wrappedTokenVault`.
3. Line 43: Emit `Deployment(msg.sender, address(asset), address(wrappedTokenVault))`.

---

### Test file 1: `test/src/concrete/deploy/StoxUnifiedDeployer.t.sol` (110 lines)

**Contract:** `StoxUnifiedDeployerTest is Test` (line 21)

**Imports (lines 4-19):**
- `Test`, `Vm` from `forge-std/Test.sol`
- `OffchainAssetReceiptVaultBeaconSetDeployer`, `OffchainAssetReceiptVaultConfigV2`, `OffchainAssetReceiptVault` from ethgild
- `StoxUnifiedDeployer` from source
- `LibProdDeployV2` from source
- `StoxWrappedTokenVault` from source
- `StoxWrappedTokenVaultBeaconSetDeployer` from source
- `LibTestDeploy` from test lib
- `ReceiptVaultConfigV2` from ethgild
- `MockERC20` from test concrete

**Test functions:**

| Line | Name | Description |
|------|------|-------------|
| 22 | `testStoxUnifiedDeployer(address asset, address vault, OffchainAssetReceiptVaultConfigV2 memory config)` | Happy path fuzz test -- mocks both deployers, asserts `Deployment` event |
| 57 | `testStoxUnifiedDeployerRevertsFirstDeployer(OffchainAssetReceiptVaultConfigV2 memory config)` | Revert propagation from first deployer (`ZeroInitialAdmin`) |
| 77 | `testStoxUnifiedDeployerRevertsSecondDeployer(address asset, OffchainAssetReceiptVaultConfigV2 memory config)` | Revert propagation from second deployer (`ZeroVaultAsset`) |

---

### Test file 2: `test/src/concrete/deploy/StoxUnifiedDeployer.newTokenAndWrapperVault.t.sol` (56 lines)

**Contract:** `StoxUnifiedDeployerIntegrationTest is Test` (line 18)

**Imports (lines 4-13):**
- `Test`, `Vm` from `forge-std/Test.sol`
- `OffchainAssetReceiptVaultConfigV2` from ethgild
- `ReceiptVaultConfigV2` from ethgild
- `StoxUnifiedDeployer` from source
- `StoxWrappedTokenVault` from source
- `LibProdDeployV2` from source
- `LibTestDeploy` from test lib

**Test functions:**

| Line | Name | Description |
|------|------|-------------|
| 20 | `testNewTokenAndWrapperVaultV2Integration()` | End-to-end V2 integration test -- deploys full Zoltu stack via `LibTestDeploy.deployAll(vm)`, calls `newTokenAndWrapperVault` with real deployers, verifies event emission and deployed vault state |

**Detailed coverage in `testNewTokenAndWrapperVaultV2Integration`:**
- Line 21: Deploys full V2 stack via Zoltu using `LibTestDeploy.deployAll(vm)`
- Line 22: Gets `StoxUnifiedDeployer` at its deterministic address
- Lines 24-32: Constructs `OffchainAssetReceiptVaultConfigV2` with `initialAdmin = address(this)`, zero asset and receipt (to be created by deployer)
- Line 34: Records logs via `vm.recordLogs()`
- Line 35: Calls `newTokenAndWrapperVault(config)` through real deployer contracts
- Lines 37-54: Iterates recorded logs checking for `Deployment` event from the unified deployer:
  - Line 42: Decodes `sender` from event data
  - Line 44: Asserts `sender == address(this)`
  - Lines 45-46: Asserts receipt vault and wrapper addresses are non-zero
  - Lines 47-48: Asserts both deployed contracts have code
  - Lines 49-51: Asserts `StoxWrappedTokenVault(wrapper).asset() == receiptVault`
- Line 54: Asserts the `Deployment` event was found

---

### Test file 3: `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` (135 lines)

**Contract:** `StoxProdBaseTest is Test` (line 24)

**Imports (lines 4-22):**
- `Test`, `Vm` from `forge-std/Test.sol`
- `StoxUnifiedDeployer` from source
- `LibProdDeployV1` from source
- `LibProdDeployV2` from source
- `LibTestProd` from test lib
- `LibTestDeploy` from test lib
- `OffchainAssetReceiptVaultBeaconSetDeployer`, `OffchainAssetReceiptVaultConfigV2` from ethgild
- `ReceiptVaultConfigV2` from ethgild
- `StoxWrappedTokenVaultBeaconSetDeployer` from source
- `IBeacon` from OpenZeppelin
- `Ownable` from OpenZeppelin
- `MockERC20` from test concrete

**Functions:**

| Line | Name | Visibility | Description |
|------|------|------------|-------------|
| 26 | `_checkAllOnChain()` | `internal view` | Verifies V1 deployed addresses and codehashes on Base fork for: OARV deployer, WTV deployer, WTV implementation (via beacon), beacon owner, unified deployer, receipt implementation, receipt vault implementation, receipt beacon owner, receipt vault beacon owner |
| 116 | `_checkUnchangedCreationBytecodes()` | `internal view` | Verifies V1 creation bytecodes for unchanged contracts (StoxReceipt, StoxReceiptVault) match compiled artifacts |
| 125 | `testProdCreationBytecodes()` | `external view` | Calls `_checkUnchangedCreationBytecodes()` |
| 130 | `testProdDeployBase()` | `external` | Fork test at pinned block -- calls `_checkAllOnChain()` |

---

### Helper file: `test/lib/LibTestDeploy.sol` (66 lines)

**Library:** `LibTestDeploy` (line 24)

**Imports (lines 5-18):**
- `Vm` from `forge-std/Vm.sol`
- `LibRainDeploy` from `rain.deploy/lib/LibRainDeploy.sol`
- `LibProdDeployV2` from source
- All Stox contract types: `StoxReceipt`, `StoxReceiptVault`, `StoxWrappedTokenVault`, `StoxWrappedTokenVaultBeacon`, `StoxWrappedTokenVaultBeaconSetDeployer`, `StoxUnifiedDeployer`, `StoxOffchainAssetReceiptVaultBeaconSetDeployer`

**Functions:**

| Line | Name | Description |
|------|------|-------------|
| 25 | `deployWrappedTokenVaultBeaconSet(Vm vm)` | Etches Zoltu factory, deploys StoxWrappedTokenVault, StoxWrappedTokenVaultBeacon, StoxWrappedTokenVaultBeaconSetDeployer via Zoltu; asserts each address matches LibProdDeployV2 |
| 43 | `deployOffchainAssetReceiptVaultBeaconSet(Vm vm)` | Etches Zoltu factory, deploys StoxReceipt, StoxReceiptVault, StoxOffchainAssetReceiptVaultBeaconSetDeployer via Zoltu; asserts each address matches LibProdDeployV2 |
| 59 | `deployAll(Vm vm)` | Calls `deployWrappedTokenVaultBeaconSet` and `deployOffchainAssetReceiptVaultBeaconSet`, then deploys StoxUnifiedDeployer via Zoltu; asserts address matches LibProdDeployV2 |

---

### Additional test coverage from other files

| File | Relevant Tests |
|------|----------------|
| `test/src/lib/LibProdDeployV2.t.sol` | `testDeployAddressStoxUnifiedDeployer` (line 90) -- Zoltu deploy produces expected address and codehash; `testCodehashStoxUnifiedDeployer` (line 122) -- fresh-compiled codehash matches V2 pointer; `testCreationCodeStoxUnifiedDeployer` (line 147) -- creation bytecode pointer matches compiler output; `testRuntimeCodeStoxUnifiedDeployer` (line 174) -- runtime bytecode pointer matches deployed bytecode; `testGeneratedAddressStoxUnifiedDeployer` (line 200) -- generated address matches library constant |
| `test/src/lib/LibProdDeployV1V2.t.sol` | `testStoxUnifiedDeployerCodehashV1DiffersV2` (line 43) -- V1 and V2 codehashes are NOT equal (confirms V2 upgrade changed the contract) |
| `test/src/concrete/deploy/StoxProdV2.t.sol` | `_checkAllV2OnChain` verifies `STOX_UNIFIED_DEPLOYER` code and codehash on-chain (line 51-52); fork tests across 5 networks (Arbitrum, Base, Base Sepolia, Flare, Polygon) |

---

## Coverage Analysis

### `newTokenAndWrapperVault` -- all logic paths

| # | Path | Tested? | Test(s) |
|---|------|---------|---------|
| 1 | Call `newOffchainAssetReceiptVault(config)` on OARV deployer with correct address | YES | `testStoxUnifiedDeployer` (mock), `testNewTokenAndWrapperVaultV2Integration` (real) |
| 2 | Pass `address(asset)` from first call to `newStoxWrappedTokenVault` on WTV deployer | YES | `testStoxUnifiedDeployer` (mock), `testNewTokenAndWrapperVaultV2Integration` (real) |
| 3 | Emit `Deployment(msg.sender, address(asset), address(wrappedTokenVault))` | YES | `testStoxUnifiedDeployer` (via `vm.expectEmit`), `testNewTokenAndWrapperVaultV2Integration` (via `vm.recordLogs`) |
| 4 | Revert propagation from first deployer | YES | `testStoxUnifiedDeployerRevertsFirstDeployer` |
| 5 | Revert propagation from second deployer | YES | `testStoxUnifiedDeployerRevertsSecondDeployer` |

### `Deployment` event

| # | Aspect | Tested? | Test(s) |
|---|--------|---------|---------|
| E1 | `sender` field matches `msg.sender` | YES | `testStoxUnifiedDeployer` (mock: `address(this)`), `testNewTokenAndWrapperVaultV2Integration` (real: `address(this)`) |
| E2 | `asset` field is the receipt vault address | YES | `testStoxUnifiedDeployer` (mock: fuzzed address), `testNewTokenAndWrapperVaultV2Integration` (real: decoded from logs, checked non-zero and has code) |
| E3 | `wrapper` field is the wrapped token vault address | YES | `testStoxUnifiedDeployer` (mock: fuzzed address), `testNewTokenAndWrapperVaultV2Integration` (real: decoded from logs, checked non-zero and has code) |
| E4 | Wrapper vault's `asset()` returns the receipt vault | YES | `testNewTokenAndWrapperVaultV2Integration` (line 49-51) |

### Deployer address correctness

| # | Aspect | Tested? | Test(s) |
|---|--------|---------|---------|
| D1 | `LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` address correct | YES | `LibProdDeployV2Test.testDeployAddressStoxOffchainAssetReceiptVaultBeaconSetDeployer`, `LibTestDeploy.deployAll` require-checks |
| D2 | `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` address correct | YES | `LibProdDeployV2Test.testDeployAddressStoxWrappedTokenVaultBeaconSetDeployer`, `LibTestDeploy.deployAll` require-checks |
| D3 | On-chain codehash of StoxUnifiedDeployer matches constant | YES | `StoxProdV2Test` fork tests across 5 networks |

### V1 fork verification

| # | Aspect | Tested? | Test(s) |
|---|--------|---------|---------|
| V1 | V1 deployment at expected address on Base | YES | `StoxProdBaseTest.testProdDeployBase` |
| V2 | V1 codehash matches constant | YES | `StoxProdBaseTest._checkAllOnChain` (lines 71-74) |
| V3 | V1 and V2 codehashes differ (confirms upgrade) | YES | `LibProdDeployV1V2Test.testStoxUnifiedDeployerCodehashV1DiffersV2` |

### Edge cases and implicit paths

| # | Scenario | Tested? | Notes |
|---|----------|---------|-------|
| X1 | Deployer address has no code deployed | NO | If `LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` has no code, the external call reverts at EVM level. Not a custom error from this contract. |
| X2 | Multiple sequential calls to `newTokenAndWrapperVault` | NO | Contract is stateless, so each call is independent. Architecturally guaranteed. |
| X3 | `config.initialAdmin == address(0)` | INDIRECT | Validation happens in downstream OARV deployer; tested via `testStoxUnifiedDeployerRevertsFirstDeployer` with mock revert |

---

### Status of prior findings

**A05-P2-1** (No revert-propagation tests): FIXED. Both `testStoxUnifiedDeployerRevertsFirstDeployer` and `testStoxUnifiedDeployerRevertsSecondDeployer` are present with specific ABI-encoded error selectors.

**A05-P2-2 / A06-P2-1** (No integration test with real deployer contracts): FIXED. `test/src/concrete/deploy/StoxUnifiedDeployer.newTokenAndWrapperVault.t.sol` implements `testNewTokenAndWrapperVaultV2Integration`, which deploys the full V2 Zoltu stack via `LibTestDeploy.deployAll(vm)` and calls `newTokenAndWrapperVault` through real deployer contracts. It verifies the `Deployment` event, non-zero addresses, deployed code existence, and `StoxWrappedTokenVault(wrapper).asset() == receiptVault`.

---

## Findings

No findings at LOW or above. Test coverage for `StoxUnifiedDeployer` is thorough across all three test files:

1. **Unit tests** (`StoxUnifiedDeployer.t.sol`) cover the happy path with fuzzed parameters and both revert-propagation paths using mocked deployers.
2. **Integration test** (`StoxUnifiedDeployer.newTokenAndWrapperVault.t.sol`) exercises the full real Zoltu deployment stack end-to-end, verifying the deployed vaults are functional.
3. **Fork/prod tests** (`StoxUnifiedDeployer.prod.base.t.sol`) verify V1 on-chain deployment state; `StoxProdV2.t.sol` verifies V2 codehashes across 5 networks.

Every reachable branch in the source contract has at least one corresponding test. The prior gap (no integration test) identified in audits 2026-03-18-01 (A05-P2-2, A06-P2-1) has been resolved.
