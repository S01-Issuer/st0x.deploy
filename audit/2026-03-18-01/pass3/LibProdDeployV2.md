# Pass 3: Documentation — LibProdDeployV2.sol

**Auditor:** A09
**Date:** 2026-03-18

---

## Evidence of Thorough Reading

**File:** `src/lib/LibProdDeployV2.sol` (65 lines)

**Library name:** `LibProdDeployV2` (line 34)

**Imports (6 generated pointer files, each providing `BYTECODE_HASH` and `DEPLOYED_ADDRESS`):**

| Pointer file | Imported names |
|---|---|
| `src/generated/StoxReceipt.pointers.sol` | `BYTECODE_HASH as STOX_RECEIPT_HASH`, `DEPLOYED_ADDRESS as STOX_RECEIPT_ADDR` |
| `src/generated/StoxReceiptVault.pointers.sol` | `BYTECODE_HASH as STOX_RECEIPT_VAULT_HASH`, `DEPLOYED_ADDRESS as STOX_RECEIPT_VAULT_ADDR` |
| `src/generated/StoxWrappedTokenVault.pointers.sol` | `BYTECODE_HASH as STOX_WRAPPED_TOKEN_VAULT_HASH`, `DEPLOYED_ADDRESS as STOX_WRAPPED_TOKEN_VAULT_ADDR` |
| `src/generated/StoxUnifiedDeployer.pointers.sol` | `BYTECODE_HASH as STOX_UNIFIED_DEPLOYER_HASH`, `DEPLOYED_ADDRESS as STOX_UNIFIED_DEPLOYER_ADDR` |
| `src/generated/StoxWrappedTokenVaultBeacon.pointers.sol` | `BYTECODE_HASH as STOX_WRAPPED_TOKEN_VAULT_BEACON_HASH`, `DEPLOYED_ADDRESS as STOX_WRAPPED_TOKEN_VAULT_BEACON_ADDR` |
| `src/generated/StoxWrappedTokenVaultBeaconSetDeployer.pointers.sol` | `BYTECODE_HASH as STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_HASH`, `DEPLOYED_ADDRESS as STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_ADDR` |

**Constants (all `constant` in a `library`, so `internal` by default):**

| Name | Line | Type | Value source |
|------|------|------|--------------|
| `STOX_RECEIPT` | 36 | `address` | `STOX_RECEIPT_ADDR` from pointer |
| `STOX_RECEIPT_CODEHASH` | 38 | `bytes32` | `STOX_RECEIPT_HASH` from pointer |
| `STOX_RECEIPT_VAULT` | 41 | `address` | `STOX_RECEIPT_VAULT_ADDR` from pointer |
| `STOX_RECEIPT_VAULT_CODEHASH` | 43 | `bytes32` | `STOX_RECEIPT_VAULT_HASH` from pointer |
| `STOX_WRAPPED_TOKEN_VAULT` | 46 | `address` | `STOX_WRAPPED_TOKEN_VAULT_ADDR` from pointer |
| `STOX_WRAPPED_TOKEN_VAULT_CODEHASH` | 48 | `bytes32` | `STOX_WRAPPED_TOKEN_VAULT_HASH` from pointer |
| `STOX_UNIFIED_DEPLOYER` | 51 | `address` | `STOX_UNIFIED_DEPLOYER_ADDR` from pointer |
| `STOX_UNIFIED_DEPLOYER_CODEHASH` | 53 | `bytes32` | `STOX_UNIFIED_DEPLOYER_HASH` from pointer |
| `STOX_WRAPPED_TOKEN_VAULT_BEACON` | 56 | `address` | `STOX_WRAPPED_TOKEN_VAULT_BEACON_ADDR` from pointer |
| `STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH` | 58 | `bytes32` | `STOX_WRAPPED_TOKEN_VAULT_BEACON_HASH` from pointer |
| `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` | 61 | `address` | `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_ADDR` from pointer |
| `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH` | 63–64 | `bytes32` | `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_HASH` from pointer |

**Functions / errors / events defined:** None.

---

## Documentation Review

### Library-level NatSpec (lines 30–33)

```solidity
/// @title LibProdDeployV2
/// @notice V2 production deployment addresses and codehashes for the Stox
/// deployment via the Zoltu deterministic deployer. Addresses are
/// deterministic and identical across all EVM networks.
```

Both `@title` and `@notice` are present and accurate. The notice correctly characterises the distinguishing feature of V2 (Zoltu deterministic deployer, cross-chain address identity) and implicitly contrasts with V1 (which was Base-specific). No inaccuracy detected.

### Per-constant NatSpec

Every constant has a `/// @dev` comment (one line for the address, one line for the codehash). The style is uniform across all 12 constants and accurately describes the constant's purpose ("Deterministic Zoltu address for X" / "Codehash of X when deployed via Zoltu").

No misleading or stale text was found in the per-constant comments.

### V1 vs V2 documentation consistency

V1 (`LibProdDeployV1`) annotates every address constant with a Basescan URL comment immediately after the `/// @dev` description:
```solidity
/// @dev The StoxUnifiedDeployer on Base.
/// https://basescan.org/address/0x821a71a313bdDDc94192CF0b5F6f5bC31Ac75853
```

V2 omits all such links. Because V2 addresses are deterministic and network-agnostic (derived from the Zoltu CREATE2 factory), a single-chain Basescan link would not fully represent the deployment and could be misleading to readers on other networks. The omission is a deliberate and reasonable trade-off. Pass 1 logged this as INFO (finding A09-1 in the Pass 1 report). No additional finding is raised here.

### Stale references or misleading descriptions

None found. All six `@dev` address comments correctly identify the contract by canonical name and the deployer mechanism ("Zoltu").

---

## Findings

### A09-P3-1: Two constant pairs (Beacon, BeaconSetDeployer) added to V2 but not covered by test suite [LOW]

**Severity:** LOW

**Location:** `src/lib/LibProdDeployV2.sol` lines 55–64 (constants `STOX_WRAPPED_TOKEN_VAULT_BEACON`, `STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH`, `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER`, `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH`); `test/src/lib/LibProdDeployV2.t.sol` (coverage gap).

**Description:**

When the Pass 2 audit was written, `LibProdDeployV2` had 8 constants (4 contract pairs: `StoxReceipt`, `StoxReceiptVault`, `StoxWrappedTokenVault`, `StoxUnifiedDeployer`). The file has since been updated to include two additional pairs:

- `STOX_WRAPPED_TOKEN_VAULT_BEACON` / `STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH` (lines 55–58)
- `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` / `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH` (lines 60–64)

The test file `test/src/lib/LibProdDeployV2.t.sol` (183 lines) covers exactly the original 4 contract pairs in a systematic pattern (Zoltu deploy address, codehash, creation code, runtime code, generated address). There are **no test functions** for `StoxWrappedTokenVaultBeacon` or `StoxWrappedTokenVaultBeaconSetDeployer`. This is confirmed by inspection: a search for "Beacon" in the test file returns no matches.

The two new address constants and their associated codehash constants therefore have zero direct test coverage in `LibProdDeployV2.t.sol`. The generated pointer files themselves are produced by `BuildPointers.sol`, but without tests that exercise the library constants, a future pointer regeneration that silently changes addresses or codehashes for these two contracts would not be caught.

**Impact:**

If `STOX_WRAPPED_TOKEN_VAULT_BEACON` or `STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER` (or their codehash companions) are wrong, nothing in the test suite will flag it. These are production deployment addresses used by `StoxUnifiedDeployer` during vault deployment; an incorrect address constant could point to a non-existent or wrong contract at runtime.

**Fix:** Add the same five test categories for the two new contract pairs to `test/src/lib/LibProdDeployV2.t.sol`: Zoltu deploy address, codehash (fresh `new`), creation code, runtime code, and generated address. See fix file `A09-P3-1.md`.

---

### A09-P3-2: Prior pass constant tables are stale — two constant pairs undocumented [INFO]

**Severity:** INFO

**Location:** `audit/2026-03-18-01/pass1/LibProdDeployV2.md`, `audit/2026-03-18-01/pass2/LibProdDeployV2.md` (audit documentation only; source code is not affected).

**Description:**

The Pass 1 and Pass 2 audit reports for this file each list only 8 constants (4 address/codehash pairs). At the time of those passes, the file may have had only 4 pairs; the Beacon and BeaconSetDeployer pairs were added in the subsequent commit (`1c7f8e4`). As a result, the Pass 2 coverage matrix and Pass 1 constant table do not reflect the current 12-constant state of the library.

This is an audit documentation gap, not a source code defect. No fix to source code is required. The meaningful consequence is captured in finding A09-P3-1 above (missing test coverage). Future pass reports for this file should use the complete 12-constant table.

No fix file required (INFO severity — audit artifact only).

---

_No other findings. Library-level NatSpec is present and accurate. Per-constant `@dev` comments are uniform and correct for all 12 constants. The Basescan-link omission (V1 vs V2 discrepancy) was previously assessed as INFO and is consistent with the network-agnostic Zoltu deployment model._
