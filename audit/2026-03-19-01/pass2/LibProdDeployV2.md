# Pass 2 (Test Coverage) - LibProdDeployV2.sol

**Agent:** A11
**File:** `src/lib/LibProdDeployV2.sol`
**Test files:**
- `test/src/lib/LibProdDeployV2.t.sol`
- `test/src/lib/LibProdDeployV1V2.t.sol`
- `test/src/concrete/deploy/StoxProdV2.t.sol`

## Evidence of Thorough Reading -- Source File

**Contract name:** `LibProdDeployV2` (library, line 38)

**Imports (lines 5-32):**
- `BYTECODE_HASH as STOX_RECEIPT_HASH`, `DEPLOYED_ADDRESS as STOX_RECEIPT_ADDR` from `../generated/StoxReceipt.pointers.sol` (lines 5-8)
- `BYTECODE_HASH as STOX_RECEIPT_VAULT_HASH`, `DEPLOYED_ADDRESS as STOX_RECEIPT_VAULT_ADDR` from `../generated/StoxReceiptVault.pointers.sol` (lines 9-12)
- `BYTECODE_HASH as STOX_WRAPPED_TOKEN_VAULT_HASH`, `DEPLOYED_ADDRESS as STOX_WRAPPED_TOKEN_VAULT_ADDR` from `../generated/StoxWrappedTokenVault.pointers.sol` (lines 13-16)
- `BYTECODE_HASH as STOX_UNIFIED_DEPLOYER_HASH`, `DEPLOYED_ADDRESS as STOX_UNIFIED_DEPLOYER_ADDR` from `../generated/StoxUnifiedDeployer.pointers.sol` (lines 17-20)
- `BYTECODE_HASH as STOX_WRAPPED_TOKEN_VAULT_BEACON_HASH`, `DEPLOYED_ADDRESS as STOX_WRAPPED_TOKEN_VAULT_BEACON_ADDR` from `../generated/StoxWrappedTokenVaultBeacon.pointers.sol` (lines 21-24)
- `BYTECODE_HASH as STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_HASH`, `DEPLOYED_ADDRESS as STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_ADDR` from `../generated/StoxWrappedTokenVaultBeaconSetDeployer.pointers.sol` (lines 25-28)
- `BYTECODE_HASH as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_HASH`, `DEPLOYED_ADDRESS as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_ADDR` from `../generated/StoxOffchainAssetReceiptVaultBeaconSetDeployer.pointers.sol` (lines 29-32)

**Functions:** None (pure constants library).

**Constants defined (lines 42-80):**
1. `BEACON_INITIAL_OWNER` (line 42) -- `address(0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b)`, hardcoded, resolves to `rainlang.eth`
2. `STOX_RECEIPT` (line 45) -- address, aliased from pointer `STOX_RECEIPT_ADDR`
3. `STOX_RECEIPT_CODEHASH` (line 47) -- bytes32, aliased from pointer `STOX_RECEIPT_HASH`
4. `STOX_RECEIPT_VAULT` (line 50) -- address, aliased from pointer `STOX_RECEIPT_VAULT_ADDR`
5. `STOX_RECEIPT_VAULT_CODEHASH` (line 52) -- bytes32, aliased from pointer `STOX_RECEIPT_VAULT_HASH`
6. `STOX_WRAPPED_TOKEN_VAULT` (line 55) -- address, aliased from pointer `STOX_WRAPPED_TOKEN_VAULT_ADDR`
7. `STOX_WRAPPED_TOKEN_VAULT_CODEHASH` (line 57) -- bytes32, aliased from pointer `STOX_WRAPPED_TOKEN_VAULT_HASH`
8. `STOX_UNIFIED_DEPLOYER` (line 60) -- address, aliased from pointer `STOX_UNIFIED_DEPLOYER_ADDR`
9. `STOX_UNIFIED_DEPLOYER_CODEHASH` (line 62) -- bytes32, aliased from pointer `STOX_UNIFIED_DEPLOYER_HASH`
10. `STOX_WRAPPED_TOKEN_VAULT_BEACON` (line 65) -- address, aliased from pointer `STOX_WRAPPED_TOKEN_VAULT_BEACON_ADDR`
11. `STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH` (line 67) -- bytes32, aliased from pointer `STOX_WRAPPED_TOKEN_VAULT_BEACON_HASH`
12. `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` (lines 70-71) -- address, aliased from pointer
13. `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH` (lines 73-74) -- bytes32, aliased from pointer
14. `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` (line 77) -- address, aliased from pointer
15. `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH` (lines 79-80) -- bytes32, aliased from pointer

**Types/errors defined:** None.

## Evidence of Thorough Reading -- Test File: LibProdDeployV2.t.sol

**Contract name:** `LibProdDeployV2Test` (line 55)

**Imports (lines 4-53):** `Test`, `LibRainDeploy`, `LibProdDeployV2`, `StoxReceipt`, `StoxReceiptVault`, `StoxWrappedTokenVault`, `StoxUnifiedDeployer`, plus CREATION_CODE/RUNTIME_CODE/DEPLOYED_ADDRESS from all 7 generated pointer files, `StoxWrappedTokenVaultBeacon`, `StoxWrappedTokenVaultBeaconSetDeployer`, `StoxOffchainAssetReceiptVaultBeaconSetDeployer`.

**Test functions (28 total):**

*Zoltu deploy address tests (7):*
- `testDeployAddressStoxReceipt()` (line 60) -- deploys via Zoltu, asserts address, code existence, codehash
- `testDeployAddressStoxReceiptVault()` (line 70) -- same pattern
- `testDeployAddressStoxWrappedTokenVault()` (line 80) -- same pattern
- `testDeployAddressStoxUnifiedDeployer()` (line 90) -- same pattern
- `testDeployAddressStoxWrappedTokenVaultBeacon()` (line 208) -- deploys WrappedTokenVault first, then beacon via Zoltu
- `testDeployAddressStoxWrappedTokenVaultBeaconSetDeployer()` (line 236) -- deploys WrappedTokenVault + beacon first, then deployer
- `testDeployAddressStoxOffchainAssetReceiptVaultBeaconSetDeployer()` (line 271) -- deploys Receipt + ReceiptVault first, then OARV deployer

*Fresh codehash tests (4):*
- `testCodehashStoxReceipt()` (line 101)
- `testCodehashStoxReceiptVault()` (line 108)
- `testCodehashStoxWrappedTokenVault()` (line 115)
- `testCodehashStoxUnifiedDeployer()` (line 122)

*Creation code tests (7):*
- `testCreationCodeStoxReceipt()` (line 130)
- `testCreationCodeStoxReceiptVault()` (line 135)
- `testCreationCodeStoxWrappedTokenVault()` (line 141)
- `testCreationCodeStoxUnifiedDeployer()` (line 147)
- `testCreationCodeStoxWrappedTokenVaultBeacon()` (line 217)
- `testCreationCodeStoxWrappedTokenVaultBeaconSetDeployer()` (line 246)
- `testCreationCodeStoxOffchainAssetReceiptVaultBeaconSetDeployer()` (line 284)

*Runtime code tests (7):*
- `testRuntimeCodeStoxReceipt()` (line 154)
- `testRuntimeCodeStoxReceiptVault()` (line 160)
- `testRuntimeCodeStoxWrappedTokenVault()` (line 167)
- `testRuntimeCodeStoxUnifiedDeployer()` (line 174)
- `testRuntimeCodeStoxWrappedTokenVaultBeacon()` (line 221)
- `testRuntimeCodeStoxWrappedTokenVaultBeaconSetDeployer()` (line 253)
- `testRuntimeCodeStoxOffchainAssetReceiptVaultBeaconSetDeployer()` (line 291)

*Generated address consistency tests (7):*
- `testGeneratedAddressStoxReceipt()` (line 182)
- `testGeneratedAddressStoxReceiptVault()` (line 188)
- `testGeneratedAddressStoxWrappedTokenVault()` (line 194)
- `testGeneratedAddressStoxUnifiedDeployer()` (line 200)
- `testGeneratedAddressStoxWrappedTokenVaultBeacon()` (line 228)
- `testGeneratedAddressStoxWrappedTokenVaultBeaconSetDeployer()` (line 261)
- `testGeneratedAddressStoxOffchainAssetReceiptVaultBeaconSetDeployer()` (line 300)

**Types/errors/constants defined in test file:** None.

## Evidence of Thorough Reading -- Test File: LibProdDeployV1V2.t.sol

**Contract name:** `LibProdDeployV1V2Test` (line 15)

**Imports (lines 5-7):** `Test`, `LibProdDeployV1`, `LibProdDeployV2`.

**Test functions (4):**
- `testStoxReceiptCodehashV1EqualsV2()` (line 17) -- asserts V1 receipt codehash == V2 receipt codehash
- `testStoxReceiptVaultCodehashV1EqualsV2()` (line 24) -- asserts V1 receipt vault codehash == V2 receipt vault codehash
- `testStoxWrappedTokenVaultCodehashV1DiffersV2()` (line 34) -- asserts V1 != V2 (intentional ZeroAsset change)
- `testStoxUnifiedDeployerCodehashV1DiffersV2()` (line 43) -- asserts V1 != V2 (V2 references V2 deployer addresses)

**Types/errors/constants defined in test file:** None.

## Evidence of Thorough Reading -- Test File: StoxProdV2.t.sol

**Contract name:** `StoxProdV2Test` (line 13)

**Imports (lines 5-7):** `Test`, `LibProdDeployV2`, `LibRainDeploy`.

**Internal helper:**
- `_checkAllV2OnChain()` (line 14) -- verifies all 7 V2 contracts exist (code.length > 0) and have expected codehash on-chain

**Test functions (5):**
- `testProdDeployArbitrumV2()` (line 56) -- forks Arbitrum, calls `_checkAllV2OnChain()`
- `testProdDeployBaseV2()` (line 62) -- forks Base, calls `_checkAllV2OnChain()`
- `testProdDeployBaseSepoliaV2()` (line 68) -- forks Base Sepolia, calls `_checkAllV2OnChain()`
- `testProdDeployFlareV2()` (line 74) -- forks Flare, calls `_checkAllV2OnChain()`
- `testProdDeployPolygonV2()` (line 80) -- forks Polygon, calls `_checkAllV2OnChain()`

**Types/errors/constants defined in test file:** None.

## Coverage Analysis

### What IS covered

**All 14 pointer-derived constants are thoroughly tested across 4 dimensions:**
1. **Zoltu deploy address correctness** -- All 7 contracts are deployed via the Zoltu factory in a local EVM environment, and the resulting addresses are asserted equal to the library constants. Code existence and codehash are also verified.
2. **Creation code consistency** -- All 7 pointer creation codes are asserted equal to `type(Contract).creationCode`, confirming the pointer files match the current compiler output.
3. **Runtime code consistency** -- All 7 pointer runtime codes are asserted equal to deployed bytecode.
4. **Generated address consistency** -- All 7 pointer addresses are asserted equal to the library constants (verifies the library correctly re-exports from pointer files).
5. **V1/V2 cross-version codehash comparison** -- 4 contracts compared (StoxReceipt/StoxReceiptVault same; StoxWrappedTokenVault/StoxUnifiedDeployer different).
6. **On-chain fork verification** -- All 7 V2 contracts verified as deployed with correct codehash across 5 networks (Arbitrum, Base, Base Sepolia, Flare, Polygon).
7. **`BEACON_INITIAL_OWNER` usage** -- Tested in `StoxWrappedTokenVaultBeacon.t.sol` (line 22) where a Zoltu deploy of the beacon confirms `owner()` matches the constant. Also tested for V1==V2 consistency (line 27).

### What is NOT covered

1. **On-chain beacon owner verification in V2 fork tests** -- `_checkAllV2OnChain()` in `StoxProdV2.t.sol` checks code existence and codehash for all 7 contracts, but does NOT verify that the on-chain `StoxWrappedTokenVaultBeacon` has the expected owner or implementation. The V1 fork test (`StoxUnifiedDeployer.prod.base.t.sol`) DOES verify beacon owners on-chain (lines 62-68, 97-108), but the V2 fork test omits this.

2. **On-chain beacon implementation verification in V2 fork tests** -- `_checkAllV2OnChain()` does not verify that `StoxWrappedTokenVaultBeacon.implementation()` returns `LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT` on-chain. The codehash check confirms the beacon contract itself is correct bytecode, but does not confirm its runtime state (which implementation the beacon currently points to).

3. **On-chain OARV deployer beacon state verification** -- `_checkAllV2OnChain()` does not verify that `StoxOffchainAssetReceiptVaultBeaconSetDeployer`'s internal beacons point to the expected implementations on-chain.

4. **`BEACON_INITIAL_OWNER` not verified on-chain as ENS** -- The constant `0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b` is documented as resolving to `rainlang.eth` via a basescan link (line 41), but no test verifies this ENS resolution on-chain.

## Findings

### A11-1: V2 fork tests do not verify beacon owner or implementation on-chain [LOW]

**Location:** `test/src/concrete/deploy/StoxProdV2.t.sol`, lines 14-53

**Description:** The `_checkAllV2OnChain()` helper verifies code existence and codehash for all 7 V2 contracts across 5 networks, but does not verify the runtime state of the `StoxWrappedTokenVaultBeacon` -- specifically its `owner()` and `implementation()` return values. This is a parity gap with the V1 fork test (`StoxUnifiedDeployer.prod.base.t.sol`, lines 50-68) which verifies beacon owner and implementation on-chain.

If the beacon's owner were transferred or the implementation were upgraded between deployment and the fork test, the codehash check alone would not detect the state change -- the bytecode of the beacon proxy contract itself is unchanged by `upgradeTo()` or `transferOwnership()` calls.

The Zoltu local deployment test in `StoxWrappedTokenVaultBeacon.t.sol` does verify owner and implementation in a freshly deployed context, but this does not confirm the on-chain deployed state.

**Severity rationale:** LOW because the beacon's codehash is verified, which confirms the bytecode is correct. The gap is that mutable on-chain state (owner, implementation) could drift post-deployment without detection by these fork tests. This is unlikely given the deterministic deployment, but the V1 fork test already sets the precedent for verifying this.

### A11-2: V2 fork tests do not verify OARV deployer beacon state on-chain [LOW]

**Location:** `test/src/concrete/deploy/StoxProdV2.t.sol`, lines 14-53

**Description:** The V1 fork test (`StoxUnifiedDeployer.prod.base.t.sol`, lines 76-108) verifies that the `OffchainAssetReceiptVaultBeaconSetDeployer`'s internal beacons (`I_RECEIPT_BEACON`, `I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON`) point to the expected implementations and have the expected owner. The V2 fork test does not perform equivalent checks for the V2 OARV deployer.

While the codehash of the V2 OARV deployer is verified (confirming the bytecode is correct and thus the constructor wired the correct constants), verifying the beacon state on-chain would confirm:
- `I_RECEIPT_BEACON().implementation()` returns the expected receipt address
- `I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON().implementation()` returns the expected vault address
- Both beacons have `BEACON_INITIAL_OWNER` as their owner

**Severity rationale:** LOW because the OARV deployer constructor hardcodes the beacon implementations from `LibProdDeployV2` constants, and the codehash is verified. However, beacon owners could transfer ownership or upgrade implementations post-deployment.

### A11-3: `BEACON_INITIAL_OWNER` ENS resolution not verified by tests [INFO]

**Location:** `src/lib/LibProdDeployV2.sol`, line 42

**Description:** The comment on line 39-41 states the address resolves to `rainlang.eth` and links to basescan. No test verifies this ENS resolution. This is documentation-only and the raw address is what matters for correctness, but if the ENS mapping ever changes, the comment could become misleading.

**Severity rationale:** INFO because the hardcoded address is what the contracts use, not the ENS name. The ENS reference is purely documentary. Verifying ENS resolution in a fork test would be fragile and network-dependent.
