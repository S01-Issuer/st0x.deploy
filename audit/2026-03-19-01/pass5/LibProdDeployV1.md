# Pass 5: Correctness / Intent Verification — LibProdDeployV1

## Agent A10

## Evidence of Reading

**File:** `src/lib/LibProdDeployV1.sol` (106 lines)
- Library: `LibProdDeployV1` (L10)
- 19 constants: `BEACON_INITIAL_OWNER` (L14), `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` (L18), `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` (L23), `STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION` (L30), `PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` (L34), `STOX_UNIFIED_DEPLOYER` (L39), `STOX_RECEIPT_IMPLEMENTATION` (L45), `PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1` (L48), `STOX_RECEIPT_VAULT_IMPLEMENTATION` (read in chunks), plus codehash and creation bytecode constants

**Test files:**
- `test/src/lib/LibProdDeployV1.t.sol` (24 lines): 2 tests verifying creation bytecodes
- `test/src/lib/LibProdDeployV1V2.t.sol` (49 lines): 4 tests verifying cross-version codehash equality/inequality
- `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` (135 lines): Fork tests with `_checkAllOnChain`, `_checkUnchangedCreationBytecodes`

## Verification

- **NatSpec accuracy:** `@title` and `@notice` describe V1 Base deployment constants. Verified: all address constants have Basescan URLs. Correct.
- **Constant accuracy:** Address constants verified against on-chain state by fork tests in `StoxUnifiedDeployer.prod.base.t.sol`. Codehash constants verified in the same fork tests. Correct.
- **Cross-version tests:** `testStoxReceiptCodehashV1EqualsV2` and `testStoxReceiptVaultCodehashV1EqualsV2` correctly assert equality for unchanged contracts. `testStoxWrappedTokenVaultCodehashV1DiffersV2` and `testStoxUnifiedDeployerCodehashV1DiffersV2` correctly assert inequality for changed contracts. All correct.
- **Creation bytecode tests:** `testCreationBytecodeStoxReceipt` and `testCreationBytecodeStoxReceiptVault` verify unchanged contracts' creation code matches compiled artifacts. Correct.
- **BEACON_INITIAL_OWNER:** Same value (`0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b`) as V2, verified by `testBeaconInitialOwnerConsistentAcrossVersions`. Correct.

## Findings

No findings.
