# Pass 1: Security — LibProdDeployV1.sol

## Evidence of Thorough Reading

**File:** `src/lib/LibProdDeployV1.sol` (99 lines)

**Library:** `LibProdDeployV1` (line 10) — constants-only, no imports, no functions, no logic.

**Constants (19 total):**

| Type | Constant | Line |
|---|---|---|
| `address` | `BEACON_INITIAL_OWNER` | 14 |
| `address` | `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | 18–19 |
| `address` | `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | 23 |
| `address` | `STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION` | 30 |
| `bytes32` | `PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` | 34–35 |
| `address` | `STOX_UNIFIED_DEPLOYER` | 39 |
| `address` | `STOX_RECEIPT_IMPLEMENTATION` | 44 |
| `bytes32` | `PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1` | 47–48 |
| `bytes` | `PROD_STOX_RECEIPT_CREATION_BYTECODE_V1` | 52 |
| `address` | `STOX_RECEIPT_VAULT_IMPLEMENTATION` | 57 |
| `bytes32` | `PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` | 60–61 |
| `bytes` | `PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V1` | 65 |
| `bytes32` | `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` | 70–71 |
| `bytes` | `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1` | 75 |
| `bytes` | `PROD_STOX_WRAPPED_TOKEN_VAULT_CREATION_BYTECODE_V1` | 79 |
| `bytes32` | `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` | 83–84 |
| `bytes` | `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1` | 88 |
| `bytes` | `PROD_STOX_UNIFIED_DEPLOYER_CREATION_BYTECODE_V1` | 92 |
| `bytes32` | `PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1` | 96–97 |

**No functions, errors, events, or types defined.** The library is a pure constants registry.

**Usage coverage:**
- All 6 codehash constants are consumed by fork tests in `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` and `test/src/lib/LibProdDeployV1V2.t.sol`.
- All 6 creation bytecode constants are consumed by `testProdCreationBytecodes` in `StoxUnifiedDeployer.prod.base.t.sol`.
- Address constants are consumed by fork tests and by `StoxUnifiedDeployer.t.sol` (via `vm.etch`).
- `BEACON_INITIAL_OWNER` is an EOA and is not verifiable on-chain via codehash (correct — no codehash constant for it).

## Findings

### A08-1: `STOX_RECEIPT_IMPLEMENTATION` and `STOX_RECEIPT_VAULT_IMPLEMENTATION` lack Basescan URL comments [INFO]

All other address constants in this file include a `/// https://basescan.org/address/...` link directly above or in the NatSpec. The two implementation addresses at lines 44 and 57 only describe their accessor path (`I_RECEIPT_BEACON.implementation()` and `I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON.implementation()`) but omit the direct Basescan URL. This is inconsistent with the pattern established by the five other address constants in the file and makes manual audit trail verification harder.

This is pre-existing pattern established in this version of the library and is an INFO-only finding (no security risk). No fix file is required.

No findings at LOW or above.
