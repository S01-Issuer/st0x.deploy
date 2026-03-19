# Pass 2 (Test Coverage) - StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol

**Agent:** A07
**File:** `src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol`

## Evidence of Thorough Reading

### Source file: `src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol` (21 lines)

**Contract:** `StoxOffchainAssetReceiptVaultBeaconSetDeployer` -- line 15

**Functions:** None defined in this file. The contract body is empty `{}` (line 21). All functionality is inherited from `OffchainAssetReceiptVaultBeaconSetDeployer`.

**Types/Errors/Constants defined:** None in this file.

**Imports:**
- `OffchainAssetReceiptVaultBeaconSetDeployer`, `OffchainAssetReceiptVaultBeaconSetDeployerConfig` (lines 5-8)
- `LibProdDeployV2` (line 9)

**Inheritance constructor args (lines 16-20):**
- `initialOwner` = `LibProdDeployV2.BEACON_INITIAL_OWNER` (resolves to `0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b`)
- `initialReceiptImplementation` = `LibProdDeployV2.STOX_RECEIPT`
- `initialOffchainAssetReceiptVaultImplementation` = `LibProdDeployV2.STOX_RECEIPT_VAULT`

---

### Parent contract: `OffchainAssetReceiptVaultBeaconSetDeployer` (ethgild, 101 lines)

**Contract:** `OffchainAssetReceiptVaultBeaconSetDeployer` -- line 36

**Struct:**
- `OffchainAssetReceiptVaultBeaconSetDeployerConfig` -- line 27 (fields: `initialOwner`, `initialReceiptImplementation`, `initialOffchainAssetReceiptVaultImplementation`)

**Event:**
- `Deployment(address sender, address offchainAssetReceiptVault, address receipt)` -- line 42

**Immutable state:**
- `I_RECEIPT_BEACON` -- `IBeacon public immutable` -- line 45
- `I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON` -- `IBeacon public immutable` -- line 48

**Functions:**
- `constructor(OffchainAssetReceiptVaultBeaconSetDeployerConfig memory config)` -- line 51
- `newOffchainAssetReceiptVault(OffchainAssetReceiptVaultConfigV2 memory config) external returns (OffchainAssetReceiptVault)` -- line 73

**Constructor error paths (lines 52-59):** `ZeroReceiptImplementation`, `ZeroVaultImplementation`, `ZeroBeaconOwner`

**`newOffchainAssetReceiptVault` error paths (lines 77-95):** `InitializeNonZeroReceipt`, `ZeroInitialAdmin`, `InitializeReceiptFailed`, `InitializeVaultFailed`

---

### Test file: `test/src/lib/LibProdDeployV2.t.sol` (306 lines)

**Contract:** `LibProdDeployV2Test is Test` -- line 55

**Tests covering `StoxOffchainAssetReceiptVaultBeaconSetDeployer`:**
- `testDeployAddressStoxOffchainAssetReceiptVaultBeaconSetDeployer()` -- line 271 (Zoltu deploy, address + codehash assertion)
- `testCreationCodeStoxOffchainAssetReceiptVaultBeaconSetDeployer()` -- line 284 (creation code matches compiler output)
- `testRuntimeCodeStoxOffchainAssetReceiptVaultBeaconSetDeployer()` -- line 291 (runtime code matches deployed code)
- `testGeneratedAddressStoxOffchainAssetReceiptVaultBeaconSetDeployer()` -- line 300 (generated pointer address matches library constant)

---

### Test file: `test/src/concrete/deploy/StoxProdV2.t.sol` (84 lines)

**Contract:** `StoxProdV2Test is Test` -- line 13

**Functions:**
- `_checkAllV2OnChain()` -- line 14 (internal helper, checks all V2 contracts on-chain)
- `testProdDeployArbitrumV2()` -- line 56
- `testProdDeployBaseV2()` -- line 62
- `testProdDeployBaseSepoliaV2()` -- line 68
- `testProdDeployFlareV2()` -- line 74
- `testProdDeployPolygonV2()` -- line 80

Lines 42-49 of `_checkAllV2OnChain` verify that `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` is deployed on-chain with matching codehash.

---

### Test helper: `test/lib/LibTestDeploy.sol` (66 lines)

**Library:** `LibTestDeploy` -- line 24

**Functions:**
- `deployWrappedTokenVaultBeaconSet(Vm vm)` -- line 25
- `deployOffchainAssetReceiptVaultBeaconSet(Vm vm)` -- line 43 (deploys StoxReceipt, StoxReceiptVault, then StoxOffchainAssetReceiptVaultBeaconSetDeployer via Zoltu, with address assertions)
- `deployAll(Vm vm)` -- line 59

---

### Integration test: `test/src/concrete/deploy/StoxUnifiedDeployer.newTokenAndWrapperVault.t.sol` (56 lines)

**Contract:** `StoxUnifiedDeployerIntegrationTest is Test` -- line 18

**Functions:**
- `testNewTokenAndWrapperVaultV2Integration()` -- line 20 (deploys full V2 stack via `LibTestDeploy.deployAll`, then calls `newTokenAndWrapperVault` with real deployers, verifies event + vault relationships)

This test exercises the real `StoxOffchainAssetReceiptVaultBeaconSetDeployer` end-to-end through `StoxUnifiedDeployer`. It verifies the receipt vault is deployed, has code, and the wrapper vault references it as its asset.

---

### Upstream ethgild tests (out of scope but checked for context)

- `OffchainAssetReceiptVaultBeaconSetDeployer.construct.t.sol` -- tests all 3 zero-address revert paths + happy path on the parent contract with arbitrary addresses
- `OffchainAssetReceiptVaultBeaconSetDeployer.newOffchainAssetReceiptVault.t.sol` -- tests `InitializeNonZeroReceipt`, `ZeroInitialAdmin`, and happy path (event, receipt manager relationship) on the parent

---

## Coverage Analysis

### Constructor (hardcoded config from LibProdDeployV2)

| Path | Tested? | Test |
|---|---|---|
| Zero-address revert for `initialReceiptImplementation` | N/A | Cannot trigger -- hardcoded to non-zero constant |
| Zero-address revert for `initialOffchainAssetReceiptVaultImplementation` | N/A | Cannot trigger -- hardcoded to non-zero constant |
| Zero-address revert for `initialOwner` | N/A | Cannot trigger -- hardcoded to non-zero constant |
| Happy path -- beacons created with correct implementations | PARTIAL | `testDeployAddressStoxOffchainAssetReceiptVaultBeaconSetDeployer` deploys via Zoltu and checks address+codehash, but does NOT assert beacon implementation addresses or beacon owner |
| Codehash matches pointer constant | YES | `testDeployAddressStoxOffchainAssetReceiptVaultBeaconSetDeployer` |
| Creation code matches compiler | YES | `testCreationCodeStoxOffchainAssetReceiptVaultBeaconSetDeployer` |
| Runtime code matches | YES | `testRuntimeCodeStoxOffchainAssetReceiptVaultBeaconSetDeployer` |
| Generated address matches library | YES | `testGeneratedAddressStoxOffchainAssetReceiptVaultBeaconSetDeployer` |

### `newOffchainAssetReceiptVault` (inherited from parent)

| Path | Tested? | Test |
|---|---|---|
| `InitializeNonZeroReceipt` when receipt != 0 | NO (on Stox deployer) | Only tested on upstream parent with different config |
| `ZeroInitialAdmin` when initialAdmin == 0 | NO (on Stox deployer) | Only tested on upstream parent |
| `InitializeReceiptFailed` | NO | Not tested anywhere on either parent or Stox deployer |
| `InitializeVaultFailed` | NO | Not tested anywhere on either parent or Stox deployer |
| Happy path -- vault + receipt deployed, initialized, event emitted | PARTIAL | Integration test `testNewTokenAndWrapperVaultV2Integration` exercises this indirectly through StoxUnifiedDeployer but does not assert the `Deployment` event from this specific deployer |

### Multi-chain fork deployment

| Path | Tested? | Test |
|---|---|---|
| Deployed on Arbitrum | YES | `testProdDeployArbitrumV2` |
| Deployed on Base | YES | `testProdDeployBaseV2` |
| Deployed on Base Sepolia | YES | `testProdDeployBaseSepoliaV2` |
| Deployed on Flare | YES | `testProdDeployFlareV2` |
| Deployed on Polygon | YES | `testProdDeployPolygonV2` |

---

## Findings

### A07-P2-6: No test verifies beacon configuration (implementation addresses and owner) on the Stox deployer [LOW]

**Location:** `src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol` lines 16-20

The constructor hardcodes `BEACON_INITIAL_OWNER`, `STOX_RECEIPT`, and `STOX_RECEIPT_VAULT` from `LibProdDeployV2`. No test deploys this contract and then asserts that `I_RECEIPT_BEACON.implementation()` equals `STOX_RECEIPT`, `I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON.implementation()` equals `STOX_RECEIPT_VAULT`, or that the beacon owners equal `BEACON_INITIAL_OWNER`.

The upstream ethgild test `testOffchainAssetReceiptVaultBeaconSetDeployerConstructSuccess` verifies these relationships on the parent with arbitrary addresses. The V1 Base fork test `testProdDeployBase` in `StoxUnifiedDeployer.prod.base.t.sol` does verify beacon owners and implementations on the V1 deployer, but no equivalent assertions exist for the V2 Stox deployer.

The codehash tests provide indirect confidence (if the codehash matches, the immutables are baked in correctly), but a regression that changes `LibProdDeployV2.STOX_RECEIPT` to the wrong address would still produce a valid codehash (just a different one), and the pointer regeneration would mask it.

The `StoxWrappedTokenVaultBeaconSetDeployer` has an analogous gap -- its test `testConstructSuccess` asserts `iStoxWrappedTokenVaultBeacon().implementation()`, but the Stox OARV deployer has no parallel.

**Severity:** LOW -- The integration test `testNewTokenAndWrapperVaultV2Integration` exercises the full deployment flow end-to-end with real implementations, which would fail if the beacons pointed to wrong contracts. But explicit assertions on beacon state would catch misconfigurations earlier and more precisely.

---

### A07-P2-7: No dedicated test file for `StoxOffchainAssetReceiptVaultBeaconSetDeployer` [INFO]

**Location:** `test/src/concrete/deploy/`

Unlike `StoxWrappedTokenVaultBeaconSetDeployer` which has `StoxWrappedTokenVaultBeaconSetDeployer.t.sol` with constructor and function tests, `StoxOffchainAssetReceiptVaultBeaconSetDeployer` has no dedicated test file. Its coverage comes from `LibProdDeployV2.t.sol` (pointer/deploy tests), the fork tests in `StoxProdV2.t.sol`, and indirect usage through `StoxUnifiedDeployer.newTokenAndWrapperVault.t.sol`.

This is arguably less of a concern than for `StoxWrappedTokenVaultBeaconSetDeployer`, because the Stox OARV deployer is a pure config wrapper with zero custom logic (the parent has all the logic), whereas `StoxWrappedTokenVaultBeaconSetDeployer` has its own function and error definitions. Nonetheless, a dedicated test that deploys the Stox deployer and verifies its beacon configuration would close the gap identified in A07-P2-6.

**Severity:** INFO
