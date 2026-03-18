# Pass 2: Test Coverage — StoxUnifiedDeployer.sol

## Evidence of Thorough Reading

### Source file: `src/concrete/deploy/StoxUnifiedDeployer.sol` (45 lines)

**Contract:** `StoxUnifiedDeployer` (line 19)
- No constructor
- No state variables
- No inheritance
- No custom errors
- No types defined in this file

**Functions:**

| Line | Name | Visibility | Mutability |
|------|------|------------|------------|
| 35 | `newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config)` | `external` | state-changing |

**Events defined:**

| Line | Name | Parameters |
|------|------|------------|
| 25 | `Deployment` | `address sender`, `address asset`, `address wrapper` (none indexed) |

**Constants used (imported from `LibProdDeployV1`):**
- `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` — `0x2191981Ca2477B745870cC307cbEB4cB2967ACe3`
- `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` — `0xeF6f9D21ED2E2742bfd3dFcf67829e4855884faB`

**Slither suppression:** `reentrancy-events` at line 34 with documented rationale (stateless contract, no exploitable reentrancy).

---

### Primary test file: `test/src/concrete/deploy/StoxUnifiedDeployer.t.sol` (104 lines)

**Contract:** `StoxUnifiedDeployerTest is Test`

**Functions:**

| Line | Name | Description |
|------|------|-------------|
| 17 | `testStoxUnifiedDeployer(address asset, address vault, OffchainAssetReceiptVaultConfigV2 memory config)` | Happy path — mocks both deployers, asserts `Deployment` event |
| 52 | `testStoxUnifiedDeployerRevertsFirstDeployer(OffchainAssetReceiptVaultConfigV2 memory config)` | Revert propagation from first deployer (`ZeroInitialAdmin`) |
| 72 | `testStoxUnifiedDeployerRevertsSecondDeployer(address asset, OffchainAssetReceiptVaultConfigV2 memory config)` | Revert propagation from second deployer (`ZeroVaultAsset`) |

---

### Fork/prod test file: `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` (128 lines)

**Contract:** `StoxProdBaseTest is Test`

**Functions:**

| Line | Name | Description |
|------|------|-------------|
| 20 | `_checkAllOnChain()` | `internal view` — verifies all prod addresses/codehashes on Base fork |
| 85 | `_checkAllCreationBytecodes()` | `internal view` — verifies all creation bytecodes match constants |
| 113 | `testProdStoxUnifiedDeployerFreshCodehash()` | Asserts fresh-compiled codehash matches `LibProdDeployV1` constant |
| 119 | `testProdCreationBytecodes()` | Asserts all creation bytecodes match constants |
| 124 | `testProdDeployBase()` | Fork test — calls `_checkAllOnChain()` at pinned block |

---

### Additional coverage found via grep

| File | Tests |
|------|-------|
| `test/src/lib/LibProdDeployV1V2.t.sol` | `testStoxUnifiedDeployerCodehashV1EqualsV2` — asserts V1 and V2 codehash constants are equal |
| `test/src/lib/LibProdDeployV2.t.sol` | `testDeployAddressStoxUnifiedDeployer` — Zoltu deploy produces expected address and codehash |
| `test/src/lib/LibProdDeployV2.t.sol` | `testCodehashStoxUnifiedDeployer` — fresh-compiled codehash matches V2 pointer constant |
| `test/src/lib/LibProdDeployV2.t.sol` | `testCreationCodeStoxUnifiedDeployer` — creation bytecode pointer matches compiler output |
| `test/src/lib/LibProdDeployV2.t.sol` | `testRuntimeCodeStoxUnifiedDeployer` — runtime bytecode pointer matches deployed bytecode |
| `test/src/lib/LibProdDeployV2.t.sol` | `testGeneratedAddressStoxUnifiedDeployer` — generated address matches library constant |

---

## Coverage Analysis

### `newTokenAndWrapperVault` — happy path

**Tested.** `testStoxUnifiedDeployer` (line 17) mocks both downstream deployers via `vm.etch` + `vm.mockCall`, calls `newTokenAndWrapperVault`, and asserts the `Deployment` event is emitted with the correct `sender`, `asset`, and `wrapper` arguments. The test is fuzz-parametric over `asset`, `vault`, and `config`.

### `Deployment` event emission

**Tested.** `vm.expectEmit()` followed by `emit StoxUnifiedDeployer.Deployment(address(this), asset, vault)` at line 46-47. This checks all three event parameters: `sender` (caller), `asset`, and `wrapper`. No event parameters are indexed, so `vm.expectEmit()` without topic-check flags still validates all three fields.

### Revert propagation — first deployer

**Tested.** `testStoxUnifiedDeployerRevertsFirstDeployer` (line 52) uses `vm.mockCallRevert` with `abi.encodeWithSignature("ZeroInitialAdmin()")` and verifies propagation with `vm.expectRevert(abi.encodeWithSignature("ZeroInitialAdmin()"))`. This is the fix proposed in A05-P2-1 and is now present in the test file.

### Revert propagation — second deployer

**Tested.** `testStoxUnifiedDeployerRevertsSecondDeployer` (line 72) uses `vm.mockCallRevert` with `abi.encodeWithSignature("ZeroVaultAsset()")` and verifies propagation. This is the fix proposed in A05-P2-1 and is now present in the test file.

### Fork test — production deployment verification

**Tested.** `testProdDeployBase` (line 124) selects the Base fork at block 43482822 and calls `_checkAllOnChain()`, which verifies:
- `StoxUnifiedDeployer` is deployed at `LibProdDeployV1.STOX_UNIFIED_DEPLOYER`
- Its codehash matches `PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1`

### Status of prior findings

**A05-P2-1** (No revert-propagation tests): Fix is implemented. Both `testStoxUnifiedDeployerRevertsFirstDeployer` and `testStoxUnifiedDeployerRevertsSecondDeployer` are present and use specific `vm.expectRevert` with ABI-encoded error selectors (no bare `vm.expectRevert()`).

**A05-P2-2** (No integration test with real deployer contracts): Fix is NOT implemented. The proposed integration test file `test/src/concrete/deploy/StoxUnifiedDeployer.integration.base.t.sol` does not exist. No test calls `newTokenAndWrapperVault` on the live Base deployment. The unit tests mock both downstream deployers rather than exercising the real beacon-proxy creation path.

---

## Findings

### A06-P2-1 (LOW): Integration test for `newTokenAndWrapperVault` against live Base deployment is absent

**Severity:** LOW

**Status of prior finding A05-P2-2:** NOT FIXED. The fix file `.fixes/A05-P2-2.md` proposed creating `test/src/concrete/deploy/StoxUnifiedDeployer.integration.base.t.sol`, but no such file exists and no equivalent coverage was added elsewhere.

**Description:** The existing unit tests for `newTokenAndWrapperVault` mock both downstream deployers (`OffchainAssetReceiptVaultBeaconSetDeployer` and `StoxWrappedTokenVaultBeaconSetDeployer`) entirely. This means the following execution paths are not covered by any test:

1. The `asset` address returned by the first deployer is passed verbatim to the second deployer — tested only by mock alignment, not by observing the actual call chain.
2. The `Deployment` event `asset` and `wrapper` fields correspond to real beacon proxy addresses that are functional `OffchainAssetReceiptVault` and `StoxWrappedTokenVault` contracts — no test verifies the deployed vault is callable after creation.
3. The ABI encoding of `config` by the Solidity compiler and its correct decoding inside `newOffchainAssetReceiptVault` is not exercised end-to-end.

The fork test `testProdDeployBase` verifies the deployed bytecode of `StoxUnifiedDeployer` at the pinned block but does not call `newTokenAndWrapperVault`. It therefore validates the contract is present, not that it functions correctly.

A fix file is proposed at `.fixes/A06-P2-1.md`.
