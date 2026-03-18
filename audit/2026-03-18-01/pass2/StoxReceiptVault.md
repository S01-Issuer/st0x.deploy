# Pass 2 — Test Coverage: StoxReceiptVault

**Agent:** A04
**File:** `src/concrete/StoxReceiptVault.sol`
**Date:** 2026-03-18

---

## Evidence of Thorough Reading

**Contract name:** `StoxReceiptVault`

**Functions defined in StoxReceiptVault:** None. The contract body is empty — it solely inherits from `OffchainAssetReceiptVault`.

**Types/Errors/Constants defined in StoxReceiptVault:** None.

**Inheritance:** `StoxReceiptVault is OffchainAssetReceiptVault`

The complete source file (11 lines) is:

```solidity
// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {OffchainAssetReceiptVault} from "ethgild/concrete/vault/OffchainAssetReceiptVault.sol";

/// @title StoxReceiptVault
/// @notice An OffchainAssetReceiptVault specialized for StoxReceipts. Currently
/// there are no modifications to the base contract, but this is here to prepare
/// for any future upgrades.
contract StoxReceiptVault is OffchainAssetReceiptVault {}
```

**Inherited public/external functions (from OffchainAssetReceiptVault, line numbers in parent):**

| Function | Line (parent) | Notes |
|---|---|---|
| `initialize(bytes)` | 301 | Real initializer; reverts if `asset != address(0)` or `initialAdmin == address(0)` |
| `highwaterId()` | 331 | View — returns current highwater id |
| `supportsInterface(bytes4)` | 337 | ERC165 |
| `authorizer()` | 342 | View — returns current authorizer |
| `authorize(address, bytes32, bytes)` | 351 | Always reverts `Unauthorized` |
| `setAuthorizer(IAuthorizeV1)` | 372 | onlyOwner |
| `authorizeReceiptTransfer3(...)` | 378 | Public override |
| `redeposit(uint256, address, uint256, bytes)` | 516 | External |
| `certify(uint256, bool, bytes)` | 582 | External |
| `isCertificationExpired()` | 608 | Public view |
| `confiscateShares(address, uint256, bytes)` | 666 | External nonReentrant |
| `confiscateReceipt(address, uint256, uint256, bytes)` | 718 | External nonReentrant |

---

## Coverage Analysis

### Direct instantiation / unit tests of StoxReceiptVault

`StoxReceiptVault` is directly instantiated in:

- `test/src/lib/LibProdDeployV2.t.sol` — three tests instantiate `new StoxReceiptVault()` and check:
  - `testCodehashStoxReceiptVault` — codehash matches constant
  - `testRuntimeCodeStoxReceiptVault` — runtime bytecode matches pointer
  - `testCreationCodeStoxReceiptVault` (pure) — creation code hash matches pointer
  - `testDeployAddressStoxReceiptVault` — Zoltu deploy produces expected address and codehash
  - `testGeneratedAddressStoxReceiptVault` (pure) — generated address matches library constant

- `test/src/lib/LibProdDeployV1V2.t.sol`:
  - `testStoxReceiptVaultCodehashV1EqualsV2` — V1 and V2 codehashes are equal

- `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` (`_checkAllOnChain`):
  - Reads the live beacon implementation address, asserts it matches `STOX_RECEIPT_VAULT_IMPLEMENTATION`, checks code is deployed, checks codehash against `PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1`
  - `_checkAllCreationBytecodes` asserts `vm.getCode("StoxReceiptVault.sol:StoxReceiptVault")` matches `PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V1`

### Functional / behavioural tests of StoxReceiptVault

**None.** There is no test file named `StoxReceiptVault.t.sol`, and no test exercises any of the inherited functions via a `StoxReceiptVault` instance. All tests instantiate the type only for bytecode / codehash comparison — they never call `initialize`, `certify`, `confiscateShares`, `confiscateReceipt`, `redeposit`, `isCertificationExpired`, `setAuthorizer`, or `authorizer` on a `StoxReceiptVault` proxy.

### Indirect coverage through deployer tests

The `StoxUnifiedDeployer` tests (`StoxUnifiedDeployer.t.sol`) mock the `OffchainAssetReceiptVaultBeaconSetDeployer` and never exercise a real `StoxReceiptVault` instance. The fork test (`StoxUnifiedDeployer.prod.base.t.sol`) only checks addresses and codehashes on mainnet, not behavioural semantics.

### Summary

| Coverage area | Status |
|---|---|
| Bytecode / codehash integrity | Covered (LibProdDeployV2.t.sol, LibProdDeployV1V2.t.sol) |
| Live on-chain address verification | Covered (prod.base.t.sol fork test) |
| `initialize(bytes)` — happy path | **NOT TESTED** |
| `initialize(bytes)` — `NonZeroAsset` revert | **NOT TESTED** |
| `initialize(bytes)` — `ZeroInitialAdmin` revert | **NOT TESTED** |
| `certify` / `isCertificationExpired` | **NOT TESTED** |
| `confiscateShares` / `confiscateReceipt` | **NOT TESTED** |
| `redeposit` | **NOT TESTED** |
| `setAuthorizer` / `authorizer` | **NOT TESTED** |
| `supportsInterface` | **NOT TESTED** |

---

## Findings

### A04-3 — LOW: No behavioural unit tests for StoxReceiptVault

**Severity:** LOW

**Description:**
`StoxReceiptVault` is the core RWA tokenisation primitive deployed in production. Although it inherits all its logic from `OffchainAssetReceiptVault`, the fact that it is a distinct deployed type means any future override, storage-layout change, or constructor modification would not be caught unless the type itself is exercised in tests. Currently, zero tests call any function on a `StoxReceiptVault` instance. Tests only compare bytecode hashes and deployment addresses.

The absence of behavioural tests means:

1. There is no regression harness: a future developer who adds an override to `StoxReceiptVault` will not know whether it works correctly or breaks the initialiser path.
2. The `initialize` → `certify` → `confiscateShares` → `confiscateReceipt` → `redeposit` flow — the vault's entire value proposition — is completely uncovered for the `StoxReceiptVault` type specifically.
3. A bare `vm.expectRevert()` is currently used for `testConstructorDisablesInitializers` on `StoxWrappedTokenVault` (line 29 of `StoxWrappedTokenVault.t.sol`); were similar tests written naively for `StoxReceiptVault`, the same defect would repeat.

**Fix:** See `.fixes/A04-3.md`.
