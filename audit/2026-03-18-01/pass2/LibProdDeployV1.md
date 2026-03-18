# Pass 2: Test Coverage — LibProdDeployV1.sol

## Evidence of Thorough Reading

**File:** `src/lib/LibProdDeployV1.sol` (99 lines)

**Library:** `LibProdDeployV1` (line 10) — constants-only, no imports, no functions, no logic.

**All constants (19 total):**

| Line | Type | Constant Name |
|---|---|---|
| 14 | `address` | `BEACON_INITIAL_OWNER` |
| 18–19 | `address` | `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` |
| 23 | `address` | `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` |
| 30 | `address` | `STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION` |
| 34–35 | `bytes32` | `PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` |
| 39 | `address` | `STOX_UNIFIED_DEPLOYER` |
| 44 | `address` | `STOX_RECEIPT_IMPLEMENTATION` |
| 47–48 | `bytes32` | `PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1` |
| 52 | `bytes` | `PROD_STOX_RECEIPT_CREATION_BYTECODE_V1` |
| 57 | `address` | `STOX_RECEIPT_VAULT_IMPLEMENTATION` |
| 60–61 | `bytes32` | `PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` |
| 65 | `bytes` | `PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V1` |
| 70–71 | `bytes32` | `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` |
| 75 | `bytes` | `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1` |
| 79 | `bytes` | `PROD_STOX_WRAPPED_TOKEN_VAULT_CREATION_BYTECODE_V1` |
| 83–84 | `bytes32` | `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` |
| 88 | `bytes` | `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1` |
| 92 | `bytes` | `PROD_STOX_UNIFIED_DEPLOYER_CREATION_BYTECODE_V1` |
| 96–97 | `bytes32` | `PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1` |

No functions, errors, events, or types defined.

## Test Files Referencing LibProdDeployV1

1. `test/src/lib/LibProdDeployV1V2.t.sol` — cross-version codehash equality/inequality checks
2. `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` — full on-chain + creation bytecode verification (Base fork)
3. `test/src/concrete/deploy/StoxUnifiedDeployer.t.sol` — unit tests using address constants as mock deployer arguments
4. `test/src/concrete/StoxWrappedTokenVaultV1.prod.base.t.sol` — V1 behaviour fork tests

## Coverage Analysis

### Address Constants

| Constant | On-chain code.length > 0 check | On-chain codehash check | Notes |
|---|---|---|---|
| `BEACON_INITIAL_OWNER` | No | N/A (EOA) | Used as immutable arg in `StoxWrappedTokenVaultBeacon`. No on-chain owner() verification. See A08-1. |
| `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | Yes (prod.base.t.sol:23) | Yes (prod.base.t.sol:27–29) | Full coverage |
| `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | Yes (prod.base.t.sol:33) | Yes (prod.base.t.sol:37–39) | Full coverage |
| `STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION` | Yes (prod.base.t.sol:54) | Yes (prod.base.t.sol:55–57) | Verified indirectly via beacon.implementation() |
| `STOX_UNIFIED_DEPLOYER` | Yes (prod.base.t.sol:60) | Yes (prod.base.t.sol:61–63) | Full coverage |
| `STOX_RECEIPT_IMPLEMENTATION` | Yes (prod.base.t.sol:70) | Yes (prod.base.t.sol:71) | Verified indirectly via I_RECEIPT_BEACON.implementation() |
| `STOX_RECEIPT_VAULT_IMPLEMENTATION` | Yes (prod.base.t.sol:80) | Yes (prod.base.t.sol:81) | Verified indirectly via I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON.implementation() |

### Codehash Constants

| Constant | Fork test codehash check | Cross-version purity check | Notes |
|---|---|---|---|
| `PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` | Yes (prod.base.t.sol:56) | Yes (LibProdDeployV1V2.t.sol:37) | Full coverage |
| `PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1` | Yes (prod.base.t.sol:71) | Yes (LibProdDeployV1V2.t.sol:19) | Full coverage |
| `PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` | Yes (prod.base.t.sol:81) | Yes (LibProdDeployV1V2.t.sol:27) | Full coverage |
| `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` | Yes (prod.base.t.sol:27–29) | None | Not cross-version checked. Acceptable: deployer is external from ethgild. |
| `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` | Yes (prod.base.t.sol:37–39) | None | Not cross-version checked. Acceptable: deployer replaced entirely in V2. |
| `PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1` | Yes (prod.base.t.sol:61–63) | Yes (LibProdDeployV1V2.t.sol:45) | Also fresh-deployed codehash check at prod.base.t.sol:114–116. Full coverage. |

### Creation Bytecode Constants

All six creation bytecode constants are verified against `vm.getCode(...)` in `_checkAllCreationBytecodes()` called by `testProdCreationBytecodes()` in `StoxUnifiedDeployer.prod.base.t.sol` (lines 86–110).

| Constant | Verified by |
|---|---|
| `PROD_STOX_RECEIPT_CREATION_BYTECODE_V1` | prod.base.t.sol:87–89 |
| `PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V1` | prod.base.t.sol:90–93 |
| `PROD_STOX_WRAPPED_TOKEN_VAULT_CREATION_BYTECODE_V1` | prod.base.t.sol:94–97 |
| `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1` | prod.base.t.sol:98–101 |
| `PROD_STOX_UNIFIED_DEPLOYER_CREATION_BYTECODE_V1` | prod.base.t.sol:102–105 |
| `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1` | prod.base.t.sol:106–109 |

### BEACON_INITIAL_OWNER Verification

`BEACON_INITIAL_OWNER` (`0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b`) is used as the constructor argument for `UpgradeableBeacon` in `StoxWrappedTokenVaultBeacon` (line 12 of that contract). In V1, the beacon was deployed via `new` inside `StoxWrappedTokenVaultBeaconSetDeployer`. The fork tests verify the beacon's `implementation()` return value (via `I_STOX_WRAPPED_TOKEN_VAULT_BEACON()`) but do **not** verify `beacon.owner()` equals `BEACON_INITIAL_OWNER`. The prior audit A07-P2-3 (BEACON_INITIAL_OWNER) was dismissed on transitive grounds, but that dismissal was based on the idea that `StoxWrappedTokenVaultBeacon` uses it as a compile-time constant — if the beacon's codehash is verified, its compiled-in `owner` is implicitly correct. The codehash of the beacon itself is not directly checked (only the deployer's codehash and the implementation's codehash are checked). The beacon's `owner()` is never queried.

## Findings

### A08-P2-1: `BEACON_INITIAL_OWNER` is never verified against the V1 on-chain beacon owner [LOW]

**Location:** `src/lib/LibProdDeployV1.sol` line 14

`BEACON_INITIAL_OWNER = address(0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b)` is used as the hard-coded initial owner for `UpgradeableBeacon` in `StoxWrappedTokenVaultBeacon`. In V1 the beacon was deployed as `new UpgradeableBeacon(impl, BEACON_INITIAL_OWNER)` inside `StoxWrappedTokenVaultBeaconSetDeployer`.

The fork tests in `StoxUnifiedDeployer.prod.base.t.sol` verify:
- The deployer's codehash (`PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1`)
- The implementation's address and codehash via `beacon.implementation()`

They do **not** query `beacon.owner()` and compare it to `BEACON_INITIAL_OWNER`. Because the V1 beacon was deployed via `new` (not Zoltu), its codehash is not stored as a constant and is not checked. The `BEACON_INITIAL_OWNER` constant is therefore untested: an error in the address literal (transposition, wrong EOA) would not be caught by any test.

The prior audit session dismissed A07-P2-3 on grounds that "BEACON_INITIAL_OWNER verified transitively." Re-examining the evidence: the deployer's codehash is verified, but the deployer's bytecode embeds the *implementation* address at construction time, not the owner — the owner is the `initialOwner` constructor argument of the beacon, which is injected at deploy time. A codehash check on the deployer does not constrain the beacon's owner. The dismissal was incorrect.

**Risk:** If `BEACON_INITIAL_OWNER` contains a wrong address, the stored constant cannot be used to recover or transfer ownership of the live V1 beacon without finding the true owner from chain state. This is a documentation integrity and operational risk.

**Proposed fix:** See `.fixes/A08-1.md`.

No additional findings at LOW or above.

### INFO: `STOX_RECEIPT_IMPLEMENTATION` and `STOX_RECEIPT_VAULT_IMPLEMENTATION` lack Basescan URL comments

(Inherited from pass 1 — no new information. No fix required.)
