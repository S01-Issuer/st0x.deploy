# Pass 2 — Test Coverage: `src/lib/LibProdDeployV2.sol`

**Auditor:** A09
**Date:** 2026-03-18

---

## Evidence of Thorough Reading

### `src/lib/LibProdDeployV2.sol`

**Library:** `LibProdDeployV2` (line 26)

**Imports (pointer files):**
| Pointer file | Imported names |
|---|---|
| `src/generated/StoxReceipt.pointers.sol` | `BYTECODE_HASH as STOX_RECEIPT_HASH`, `DEPLOYED_ADDRESS as STOX_RECEIPT_ADDR` |
| `src/generated/StoxReceiptVault.pointers.sol` | `BYTECODE_HASH as STOX_RECEIPT_VAULT_HASH`, `DEPLOYED_ADDRESS as STOX_RECEIPT_VAULT_ADDR` |
| `src/generated/StoxWrappedTokenVault.pointers.sol` | `BYTECODE_HASH as STOX_WRAPPED_TOKEN_VAULT_HASH`, `DEPLOYED_ADDRESS as STOX_WRAPPED_TOKEN_VAULT_ADDR` |
| `src/generated/StoxUnifiedDeployer.pointers.sol` | `BYTECODE_HASH as STOX_UNIFIED_DEPLOYER_HASH`, `DEPLOYED_ADDRESS as STOX_UNIFIED_DEPLOYER_ADDR` |

**Constants:**
| Name | Line | Type | Value source |
|---|---|---|---|
| `STOX_RECEIPT` | 28 | `address` | `STOX_RECEIPT_ADDR` from pointer |
| `STOX_RECEIPT_CODEHASH` | 30 | `bytes32` | `STOX_RECEIPT_HASH` from pointer |
| `STOX_RECEIPT_VAULT` | 33 | `address` | `STOX_RECEIPT_VAULT_ADDR` from pointer |
| `STOX_RECEIPT_VAULT_CODEHASH` | 35 | `bytes32` | `STOX_RECEIPT_VAULT_HASH` from pointer |
| `STOX_WRAPPED_TOKEN_VAULT` | 38 | `address` | `STOX_WRAPPED_TOKEN_VAULT_ADDR` from pointer |
| `STOX_WRAPPED_TOKEN_VAULT_CODEHASH` | 40 | `bytes32` | `STOX_WRAPPED_TOKEN_VAULT_HASH` from pointer |
| `STOX_UNIFIED_DEPLOYER` | 43 | `address` | `STOX_UNIFIED_DEPLOYER_ADDR` from pointer |
| `STOX_UNIFIED_DEPLOYER_CODEHASH` | 45 | `bytes32` | `STOX_UNIFIED_DEPLOYER_HASH` from pointer |

---

### `test/src/lib/LibProdDeployV2.t.sol`

**Contract:** `LibProdDeployV2Test` (line 33) — extends `forge-std/Test.sol`

**Imports:**
- `LibRainDeploy` from `rain.deploy/lib/LibRainDeploy.sol`
- `LibProdDeployV2`
- `StoxReceipt`, `StoxReceiptVault`, `StoxWrappedTokenVault`, `StoxUnifiedDeployer` (for `creationCode`)
- `CREATION_CODE`, `RUNTIME_CODE`, `DEPLOYED_ADDRESS` from all four pointer files

**Test functions:**
| Name | Lines | Mutability | What it checks |
|---|---|---|---|
| `testDeployAddressStoxReceipt()` | 38–44 | external | Zoltu deploy → address == `STOX_RECEIPT`, codehash == `STOX_RECEIPT_CODEHASH` |
| `testDeployAddressStoxReceiptVault()` | 48–54 | external | Zoltu deploy → address == `STOX_RECEIPT_VAULT`, codehash == `STOX_RECEIPT_VAULT_CODEHASH` |
| `testDeployAddressStoxWrappedTokenVault()` | 58–64 | external | Zoltu deploy → address == `STOX_WRAPPED_TOKEN_VAULT`, codehash == `STOX_WRAPPED_TOKEN_VAULT_CODEHASH` |
| `testDeployAddressStoxUnifiedDeployer()` | 68–74 | external | Zoltu deploy → address == `STOX_UNIFIED_DEPLOYER`, codehash == `STOX_UNIFIED_DEPLOYER_CODEHASH` |
| `testCodehashStoxReceipt()` | 79–82 | external | fresh `new` codehash == `STOX_RECEIPT_CODEHASH` |
| `testCodehashStoxReceiptVault()` | 86–89 | external | fresh `new` codehash == `STOX_RECEIPT_VAULT_CODEHASH` |
| `testCodehashStoxWrappedTokenVault()` | 93–96 | external | fresh `new` codehash == `STOX_WRAPPED_TOKEN_VAULT_CODEHASH` |
| `testCodehashStoxUnifiedDeployer()` | 100–103 | external | fresh `new` codehash == `STOX_UNIFIED_DEPLOYER_CODEHASH` |
| `testCreationCodeStoxReceipt()` | 108–110 | external pure | pointer creation code hash == compiler output |
| `testCreationCodeStoxReceiptVault()` | 113–115 | external pure | pointer creation code hash == compiler output |
| `testCreationCodeStoxWrappedTokenVault()` | 119–123 | external pure | pointer creation code hash == compiler output |
| `testCreationCodeStoxUnifiedDeployer()` | 127–129 | external pure | pointer creation code hash == compiler output |
| `testRuntimeCodeStoxReceipt()` | 134–137 | external | pointer runtime code hash == deployed bytecode |
| `testRuntimeCodeStoxReceiptVault()` | 140–143 | external | pointer runtime code hash == deployed bytecode |
| `testRuntimeCodeStoxWrappedTokenVault()` | 147–150 | external | pointer runtime code hash == deployed bytecode |
| `testRuntimeCodeStoxUnifiedDeployer()` | 154–157 | external | pointer runtime code hash == deployed bytecode |
| `testGeneratedAddressStoxReceipt()` | 162–164 | external pure | pointer `DEPLOYED_ADDRESS` == `STOX_RECEIPT` |
| `testGeneratedAddressStoxReceiptVault()` | 168–170 | external pure | pointer `DEPLOYED_ADDRESS` == `STOX_RECEIPT_VAULT` |
| `testGeneratedAddressStoxWrappedTokenVault()` | 174–176 | external pure | pointer `DEPLOYED_ADDRESS` == `STOX_WRAPPED_TOKEN_VAULT` |
| `testGeneratedAddressStoxUnifiedDeployer()` | 180–182 | external pure | pointer `DEPLOYED_ADDRESS` == `STOX_UNIFIED_DEPLOYER` |

---

### `test/src/lib/LibProdDeployV1V2.t.sol`

**Contract:** `LibProdDeployV1V2Test` (line 15) — extends `forge-std/Test.sol`

**Test functions:**
| Name | Lines | What it checks |
|---|---|---|
| `testStoxReceiptCodehashV1EqualsV2()` | 17–22 | V1 codehash == V2 codehash (unchanged contract) |
| `testStoxReceiptVaultCodehashV1EqualsV2()` | 25–30 | V1 codehash == V2 codehash (unchanged contract) |
| `testStoxWrappedTokenVaultCodehashV1DiffersV2()` | 35–40 | V1 codehash != V2 codehash (confirms ZeroAsset change) |
| `testStoxUnifiedDeployerCodehashV1EqualsV2()` | 43–48 | V1 codehash == V2 codehash (unchanged contract) |

---

## Coverage Analysis

### `STOX_RECEIPT` (address constant, line 28)

- **Zoltu deploy simulation:** YES — `testDeployAddressStoxReceipt()` etches the Zoltu factory via `LibRainDeploy.etchZoltuFactory(vm)` and deploys with `type(StoxReceipt).creationCode`, asserting the resulting address equals `STOX_RECEIPT`.
- **Codehash verified against compiled artifact:** YES — via `testCodehashStoxReceipt()` (`new StoxReceipt()`) and `testDeployAddressStoxReceipt()` (post-Zoltu-deploy). Both assert `codehash == STOX_RECEIPT_CODEHASH`.
- **Cross-version consistency (V1 vs V2):** YES — `testStoxReceiptCodehashV1EqualsV2()` asserts V1 and V2 codehashes are equal (contract unchanged between versions).
- **Creation bytecode verified:** YES — `testCreationCodeStoxReceipt()` compares `keccak256(CREATION_CODE)` with `keccak256(type(StoxReceipt).creationCode)`.
- **Runtime code verified:** YES — `testRuntimeCodeStoxReceipt()` compares `keccak256(RUNTIME_CODE)` against deployed bytecode from `new StoxReceipt()`.
- **Pointer address consistency:** YES — `testGeneratedAddressStoxReceipt()` asserts the pointer file's `DEPLOYED_ADDRESS` equals `STOX_RECEIPT`.
- **On-chain fork verification of V2 address:** NO — no fork test checks that `STOX_RECEIPT` is actually deployed on Base mainnet at the V2 address.

### `STOX_RECEIPT_CODEHASH` (bytes32 constant, line 30)

- Covered comprehensively via Zoltu simulation, fresh-compile, and V1/V2 cross-check. See `STOX_RECEIPT` above.
- **On-chain fork verification:** NO.

### `STOX_RECEIPT_VAULT` (address constant, line 33)

- **Zoltu deploy simulation:** YES — `testDeployAddressStoxReceiptVault()`.
- **Codehash verified against compiled artifact:** YES — `testCodehashStoxReceiptVault()` and Zoltu test.
- **Cross-version consistency:** YES — `testStoxReceiptVaultCodehashV1EqualsV2()`.
- **Creation bytecode verified:** YES — `testCreationCodeStoxReceiptVault()`.
- **Runtime code verified:** YES — `testRuntimeCodeStoxReceiptVault()`.
- **Pointer address consistency:** YES — `testGeneratedAddressStoxReceiptVault()`.
- **On-chain fork verification of V2 address:** NO.

### `STOX_RECEIPT_VAULT_CODEHASH` (bytes32 constant, line 35)

- Covered via the same suite as `STOX_RECEIPT_VAULT`.
- **On-chain fork verification:** NO.

### `STOX_WRAPPED_TOKEN_VAULT` (address constant, line 38)

- **Zoltu deploy simulation:** YES — `testDeployAddressStoxWrappedTokenVault()`.
- **Codehash verified against compiled artifact:** YES — `testCodehashStoxWrappedTokenVault()`.
- **Cross-version consistency:** YES — `testStoxWrappedTokenVaultCodehashV1DiffersV2()` asserts V1 != V2 (intentional; V2 adds ZeroAsset check).
- **Creation bytecode verified:** YES — `testCreationCodeStoxWrappedTokenVault()`.
- **Runtime code verified:** YES — `testRuntimeCodeStoxWrappedTokenVault()`.
- **Pointer address consistency:** YES — `testGeneratedAddressStoxWrappedTokenVault()`.
- **On-chain fork verification of V2 address:** NO.

### `STOX_WRAPPED_TOKEN_VAULT_CODEHASH` (bytes32 constant, line 40)

- Covered via the same suite as `STOX_WRAPPED_TOKEN_VAULT`.
- **On-chain fork verification:** NO.

### `STOX_UNIFIED_DEPLOYER` (address constant, line 43)

- **Zoltu deploy simulation:** YES — `testDeployAddressStoxUnifiedDeployer()`.
- **Codehash verified against compiled artifact:** YES — `testCodehashStoxUnifiedDeployer()`.
- **Cross-version consistency:** YES — `testStoxUnifiedDeployerCodehashV1EqualsV2()`.
- **Creation bytecode verified:** YES — `testCreationCodeStoxUnifiedDeployer()`.
- **Runtime code verified:** YES — `testRuntimeCodeStoxUnifiedDeployer()`.
- **Pointer address consistency:** YES — `testGeneratedAddressStoxUnifiedDeployer()`.
- **On-chain fork verification of V2 address:** NO.

### `STOX_UNIFIED_DEPLOYER_CODEHASH` (bytes32 constant, line 45)

- Covered via the same suite as `STOX_UNIFIED_DEPLOYER`.
- **On-chain fork verification:** NO.

---

## Summary: Coverage Matrix

| Constant | Zoltu sim | Fresh codehash | V1/V2 cross | Creation code | Runtime code | Pointer addr | On-chain fork |
|---|---|---|---|---|---|---|---|
| `STOX_RECEIPT` | YES | YES | YES (equal) | YES | YES | YES | NO |
| `STOX_RECEIPT_CODEHASH` | YES | YES | YES | — | — | — | NO |
| `STOX_RECEIPT_VAULT` | YES | YES | YES (equal) | YES | YES | YES | NO |
| `STOX_RECEIPT_VAULT_CODEHASH` | YES | YES | YES | — | — | — | NO |
| `STOX_WRAPPED_TOKEN_VAULT` | YES | YES | YES (differs) | YES | YES | YES | NO |
| `STOX_WRAPPED_TOKEN_VAULT_CODEHASH` | YES | YES | YES | — | — | — | NO |
| `STOX_UNIFIED_DEPLOYER` | YES | YES | YES (equal) | YES | YES | YES | NO |
| `STOX_UNIFIED_DEPLOYER_CODEHASH` | YES | YES | YES | — | — | — | NO |

---

## Findings

### A09-1 — LOW: No fork test verifies V2 addresses are actually deployed on Base mainnet

**Severity:** LOW

**Location:** `test/src/lib/LibProdDeployV2.t.sol` — coverage gap; `src/lib/LibProdDeployV2.sol` lines 28, 33, 38, 43 (the four address constants).

**Description:**
The V2 test suite thoroughly covers the Zoltu deterministic-address computation (in-process simulation), fresh-compile codehash agreement, creation bytecode identity, runtime code identity, and pointer-file consistency. What is entirely absent is a fork test that creates a Base mainnet fork and verifies:

1. Each V2 address (`STOX_RECEIPT`, `STOX_RECEIPT_VAULT`, `STOX_WRAPPED_TOKEN_VAULT`, `STOX_UNIFIED_DEPLOYER`) has `code.length > 0` at the pinned block.
2. Each V2 address has `codehash` equal to the corresponding V2 codehash constant.

This is in contrast to V1, which has `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` (`testProdDeployBase()`) performing exactly this check for all V1 addresses. V2 is missing an equivalent.

**Impact:**
If V2 contracts have not been deployed on Base (or were deployed at different addresses, or with different bytecode due to a build flag mismatch), the mismatch would not be caught by the existing suite. The Zoltu simulation proves the Zoltu formula is correct, but does not prove the transaction was actually broadcast. A fork test is the only way to confirm on-chain reality.

**Note:** This is the only coverage gap identified. All other axes — Zoltu address derivation, codehash vs. compiler, creation code, runtime code, pointer file consistency, and cross-version (V1 vs. V2) relationships — are comprehensively tested. The severity is LOW because the Zoltu simulation provides strong determinism guarantees; a fork test is belt-and-suspenders confirmation.

---

_No other findings. All constants are sourced from auto-generated pointer files. The pointer files themselves are verified by the creation-code and runtime-code tests in the same test contract. The V1/V2 cross-check test correctly documents intentional divergence (WrappedTokenVault) and intended equality (Receipt, ReceiptVault, UnifiedDeployer)._
