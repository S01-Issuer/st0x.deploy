# Pass 3 Audit: LibProdDeployV1.sol

**Auditor:** A08
**Date:** 2026-03-18
**File:** `src/lib/LibProdDeployV1.sol`

---

## 1. Evidence of Thorough Reading

**Library:** `LibProdDeployV1` (line 10)

**Constants (by line):**

| Line | Type | Name |
|------|------|------|
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

Total: 19 constants across 5 types (address, bytes32, bytes).

---

## 2. Documentation Review

### NatSpec on the library

The library has `@title` (line 5) and `@notice` (lines 6–8) NatSpec. **Prior finding A07-P3-1 is FIXED.**

### NatSpec on constants

Every constant has an `@dev` comment describing its role. **Prior finding A07-P3-2 is FIXED.**

The codehash constant `PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1` has a two-line `@dev` comment (lines 32–33). **Prior finding A07-P3-3 (missing codehash comment) is FIXED.**

### Basescan URLs on address constants

Address constants with Basescan URLs:

| Constant | Has URL |
|----------|---------|
| `BEACON_INITIAL_OWNER` | Yes (line 13) |
| `OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER` | Yes (line 17) |
| `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | Yes (line 22) |
| `STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION` | Yes (line 29) |
| `STOX_UNIFIED_DEPLOYER` | Yes (line 38) |
| `STOX_RECEIPT_IMPLEMENTATION` | **No** |
| `STOX_RECEIPT_VAULT_IMPLEMENTATION` | **No** |

`STOX_RECEIPT_IMPLEMENTATION` (line 44) and `STOX_RECEIPT_VAULT_IMPLEMENTATION` (line 57) each have a
multi-line `@dev` description of what they represent, but neither carries a Basescan URL comment.
This was noted in Pass 1 and remains unaddressed.

All other address constants, codehash constants, and bytecode constants are documented consistently.
Non-address constants (bytes32 codehashes and bytes creation bytecodes) do not require Basescan URLs.

---

## 3. Findings

### A08-P3-1 [LOW]: `STOX_RECEIPT_IMPLEMENTATION` and `STOX_RECEIPT_VAULT_IMPLEMENTATION` missing Basescan URL comments

**Severity:** LOW
**Lines:** 41–44 (`STOX_RECEIPT_IMPLEMENTATION`), 54–57 (`STOX_RECEIPT_VAULT_IMPLEMENTATION`)

Every other address constant in `LibProdDeployV1` includes an inline Basescan URL comment as part
of its `@dev` block, enabling direct verification against the live deployment. These two constants
do not follow that pattern: their `@dev` comments describe the role of the address but omit the URL.

This is an inconsistency in documentation quality — a reader cannot one-click-verify the deployed
addresses without manually searching Basescan.

**Fix file:** `.fixes/A08-P3-1.md`

---

## 4. Prior-finding Verification Summary

| Finding | Status |
|---------|--------|
| A07-P3-1 (no library NatSpec) | FIXED — `@title` and `@notice` present |
| A07-P3-2 (no constant NatSpec) | FIXED — every constant has `@dev` |
| A07-P3-3 (missing codehash comment) | FIXED — codehash has `@dev` description |
| Pass 1 note (missing Basescan URLs on receipt constants) | NOT FIXED — raised as A08-P3-1 |
