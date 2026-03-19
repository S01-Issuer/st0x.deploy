# Pass 3 (Documentation) -- LibProdDeployV1.sol

**Agent:** A10
**Date:** 2026-03-19
**File:** `src/lib/LibProdDeployV1.sol`

---

## 1. Evidence of Thorough Reading

**Library:** `LibProdDeployV1` (line 10)

**Library-level NatSpec:** `@title` (line 5), `@notice` (lines 6-8)

**Annotations:** `slither-disable-next-line too-many-digits` (line 9)

**Constants (19 total):**

| Line | Type | Name | Has `@dev` | Has Basescan URL |
|------|------|------|-----------|-----------------|
| 14 | `address` | `BEACON_INITIAL_OWNER` | Yes (lines 11-13) | Yes (line 13) |
| 18-19 | `address` | `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | Yes (lines 16-17) | Yes (line 17) |
| 23 | `address` | `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | Yes (lines 21-22) | Yes (line 22) |
| 30 | `address` | `STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION` | Yes (lines 25-29) | Yes (line 29) |
| 34-35 | `bytes32` | `PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` | Yes (lines 32-33) | N/A |
| 39 | `address` | `STOX_UNIFIED_DEPLOYER` | Yes (lines 37-38) | Yes (line 38) |
| 45 | `address` | `STOX_RECEIPT_IMPLEMENTATION` | Yes (lines 41-44) | Yes (line 44) |
| 48-49 | `bytes32` | `PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1` | Yes (lines 47-48) | N/A |
| 53-54 | `bytes` | `PROD_STOX_RECEIPT_CREATION_BYTECODE_V1` | Yes (lines 51-52) | N/A |
| 60 | `address` | `STOX_RECEIPT_VAULT_IMPLEMENTATION` | Yes (lines 56-59) | Yes (line 59) |
| 63-64 | `bytes32` | `PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` | Yes (lines 62-63) | N/A |
| 68-69 | `bytes` | `PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V1` | Yes (lines 66-67) | N/A |
| 74-75 | `bytes32` | `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` | Yes (lines 71-73) | N/A |
| 79-80 | `bytes` | `PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1` | Yes (lines 77-78) | N/A |
| 84-85 | `bytes` | `PROD_STOX_WRAPPED_TOKEN_VAULT_CREATION_BYTECODE_V1` | Yes (lines 82-83) | N/A |
| 89-90 | `bytes32` | `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1` | Yes (lines 87-89) | N/A |
| 94-95 | `bytes` | `PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V1` | Yes (lines 92-93) | N/A |
| 99-100 | `bytes` | `PROD_STOX_UNIFIED_DEPLOYER_CREATION_BYTECODE_V1` | Yes (lines 97-98) | N/A |
| 104-105 | `bytes32` | `PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1` | Yes (lines 102-103) | N/A |

---

## 2. Documentation Review

### Library-level NatSpec

Complete. `@title LibProdDeployV1` and `@notice` describing purpose (V1 production deployment addresses, codehashes, and creation bytecodes for the Stox deployment on Base, recording the initial non-Zoltu deployment).

### Constant-level NatSpec

All 19 constants have `@dev` documentation. Every address constant includes a Basescan URL. Non-address constants (codehashes and creation bytecodes) do not require Basescan URLs and correctly omit them.

### Basescan URL Verification

All 7 address constants carry Basescan URLs. Each URL was verified to match the corresponding Solidity address literal (case-insensitive comparison, as Basescan URLs use lowercase while Solidity uses EIP-55 checksummed casing):

| Constant | URL address | Code address | Match |
|----------|------------|--------------|-------|
| `BEACON_INITIAL_OWNER` | `0x8E4bdeec...329f5b` | `0x8E4bdeec...329f5b` | Yes |
| `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | `0x2191981ca...7ace3` | `0x2191981Ca...7ACe3` | Yes (case) |
| `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | `0xef6f9d21...84fab` | `0xeF6f9D21...84faB` | Yes (case) |
| `STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION` | `0x80A79767...a1eD1` | `0x80A79767...a1eD1` | Yes |
| `STOX_UNIFIED_DEPLOYER` | `0x821a71a3...5853` | `0x821a71a3...5853` | Yes |
| `STOX_RECEIPT_IMPLEMENTATION` | `0xE7573879...CbCD` | `0xE7573879...CbCD` | Yes |
| `STOX_RECEIPT_VAULT_IMPLEMENTATION` | `0x8EFfCe5E...9f39` | `0x8EFfCe5E...9f39` | Yes |

### Slither Annotation

Line 9: `// slither-disable-next-line too-many-digits` -- suppresses the `too-many-digits` detector for the entire library. No explanatory comment accompanies the annotation.

### Potentially Stale Comment

Lines 27-28: `iStoxWrappedTokenVaultBeacon.implementation(). No proxy instances have been deployed on Base yet.` -- This was accurate at V1 deployment time. As a V1 audit-trail file, this historical comment is reasonable, but could be misleading to a reader unaware that V2 has since been deployed and proxies may now exist.

---

## 3. Findings

### A10-1 [LOW] Slither-disable annotation on line 9 lacks an explanatory comment

**Line:** 9

The `slither-disable-next-line too-many-digits` annotation suppresses a slither warning for the library but provides no comment explaining why the suppression is needed. Per project CLAUDE.md: "Always add a comment explaining why when adding `slither-disable` annotations."

The suppression is correct -- the library inherently contains many long hex literals (addresses, codehashes, and creation bytecodes) that trigger the detector. But the annotation should document this rationale inline.

This was also noted in Pass 1 (A10-1 [INFO]) of this audit round. Escalating to LOW here as it is a documentation-specific pass and the omission directly violates a stated project convention for inline documentation.

**Fix file:** `.fixes/A10-P3-1.md`

### A10-2 [INFO] "No proxy instances" comment may be historically misleading

**Lines:** 27-28

The `@dev` comment for `STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION` states "No proxy instances have been deployed on Base yet." This was written at V1 deployment time. Since this is a V1 audit-trail file (not active production code), the comment is historically accurate. However, a reader unfamiliar with the versioning may interpret it as a current-state assertion.

No fix proposed -- the comment is accurate in historical context and the file is explicitly documented as a V1 audit trail.

---

## 4. Prior-finding Verification Summary

| Prior Finding | Status |
|---------------|--------|
| A08-P3-1 (missing Basescan URLs on `STOX_RECEIPT_IMPLEMENTATION` and `STOX_RECEIPT_VAULT_IMPLEMENTATION`) | **FIXED** -- both now have URLs (lines 44, 59) |
| A07-P3-1 (no library NatSpec) | **FIXED** -- `@title` and `@notice` present (lines 5-8) |
| A07-P3-2 (no constant NatSpec) | **FIXED** -- every constant has `@dev` |
| A07-P3-3 (missing codehash comment) | **FIXED** -- codehash has `@dev` description |
| A10-1 from Pass 1 (slither annotation lacks comment) | **NOT FIXED** -- raised here as A10-1 |
