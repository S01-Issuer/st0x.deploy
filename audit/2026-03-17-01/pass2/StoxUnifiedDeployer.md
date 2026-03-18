# Pass 2: Test Coverage — A05: StoxUnifiedDeployer.sol

## Evidence of Thorough Reading

**Source:** `src/concrete/deploy/StoxUnifiedDeployer.sol` (41 lines)
- Contract: `StoxUnifiedDeployer` (line 19) — no constructor, no state, no inheritance
- Event: `Deployment(address sender, address asset, address wrapper)` (line 25)
- Function: `newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config)` (line 31, external)

**Test:** `test/src/concrete/deploy/StoxUnifiedDeployer.t.sol` (50 lines)
- Contract: `StoxUnifiedDeployerTest` (line 16)
- Function: `testStoxUnifiedDeployer(address, address, OffchainAssetReceiptVaultConfigV2)` (line 17) — fuzz test with vm.etch/vm.mockCall

**Test:** `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` (24 lines)
- Contract: `StoxUnifiedDeployerProdBaseTest` (line 12)
- Function: `testProdStoxUnifiedDeployerBase()` (line 13) — codehash verification on Base fork

**Library:** `test/lib/LibTestProd.sol` (13 lines)
- Library: `LibTestProd` (line 9)
- Function: `createSelectForkBase(Vm)` (line 10) — forks Base at block 41300535

## Coverage Analysis

The unit test covers the happy path with mocked deployers. The prod test verifies codehash only.

## Findings

### A05-P2-1: No revert-propagation tests for downstream deployer failures [LOW]

The unit test only covers the happy path. The two external calls can each revert for multiple reasons (`ZeroInitialAdmin`, `ZeroVaultAsset`, etc.). Since `StoxUnifiedDeployer` has no `try/catch`, these should bubble up, but no test confirms this. Low risk because the code is trivially pass-through, but no regression guard exists.

### A05-P2-2: No integration test with real deployer contracts [LOW]

The test uses `vm.etch`/`vm.mockCall` exclusively. The actual beacon proxy creation, initialization, and ABI encoding/decoding between contracts are never exercised in the context of `StoxUnifiedDeployer`. A fork-based integration test calling `newTokenAndWrapperVault` on the real Base deployment would close this gap.

### A05-P2-3: Prod test does not verify runtime behavior [INFO]

The prod test verifies codehash equivalence but never calls `newTokenAndWrapperVault` on the forked chain. If the on-chain deployer's hardcoded addresses pointed to broken deployers, the test would still pass.
