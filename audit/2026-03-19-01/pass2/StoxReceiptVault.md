# Pass 2 (Test Coverage) — StoxReceiptVault

**Agent:** A04
**File:** `src/concrete/StoxReceiptVault.sol`
**Test file:** `test/src/concrete/StoxReceiptVault.t.sol`
**Date:** 2026-03-19

---

## Evidence of Thorough Reading — Source File

**File:** `src/concrete/StoxReceiptVault.sol` (11 lines)

**Contract:** `StoxReceiptVault` (line 11)

**Functions defined:** None. The contract body is empty (`{}`).

**Types/Errors/Constants defined:** None.

**Imports:**
- `OffchainAssetReceiptVault` from `ethgild/concrete/vault/OffchainAssetReceiptVault.sol` (line 5)

**Inheritance:** `StoxReceiptVault is OffchainAssetReceiptVault` (line 11)

The contract is an intentionally empty wrapper around `OffchainAssetReceiptVault`. It inherits all behavior from the parent, including:
- Constructor (from `ReceiptVault`, line 124-126 in ethgild) that calls `_disableInitializers()`
- `initialize(bytes)` (line 301 in parent) — real initializer returning `ICLONEABLE_V2_SUCCESS`
- `highwaterId()` (line 331), `supportsInterface(bytes4)` (line 337), `authorizer()` (line 342)
- `authorize(address, bytes32, bytes)` (line 351) — always reverts `Unauthorized`
- `setAuthorizer(IAuthorizeV1)` (line 372) — onlyOwner
- `authorizeReceiptTransfer3(...)` (line 378)
- `_beforeDeposit(...)` (line 406), `_afterDeposit(...)` (line 423), `_afterWithdraw(...)` (line 449)
- `totalAssets()` (line 478), `_nextId()` (line 486)
- `redeposit(uint256, address, uint256, bytes)` (line 516)
- `certify(uint256, bool, bytes)` (line 582), `isCertificationExpired()` (line 608)
- `_update(address, address, uint256)` (line 615)
- `confiscateShares(address, uint256, bytes)` (line 666)
- `confiscateReceipt(address, uint256, uint256, bytes)` (line 718)

---

## Evidence of Thorough Reading — Test File

**File:** `test/src/concrete/StoxReceiptVault.t.sol` (16 lines)

**Contract:** `StoxReceiptVaultTest is Test` (line 9)

**Functions:**
- `testConstructorDisablesInitializers()` (line 11) — creates a new `StoxReceiptVault` implementation, expects `Initializable.InvalidInitialization` revert on `initialize(abi.encode(address(1)))`

**Imports:**
- `Test` from `forge-std/Test.sol` (line 5)
- `StoxReceiptVault` from `../../../src/concrete/StoxReceiptVault.sol` (line 6)
- `Initializable` from `openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol` (line 7)

---

## Coverage Analysis

### Direct tests in StoxReceiptVault.t.sol

| Test | What it covers |
|---|---|
| `testConstructorDisablesInitializers` (line 11) | Constructor calls `_disableInitializers()`; `initialize()` reverts on implementation |

### Indirect coverage via other test files

| Test file | Coverage |
|---|---|
| `test/src/lib/LibProdDeployV2.t.sol` | Bytecode/codehash integrity (5 tests: deploy address, codehash, creation code, runtime code, generated address) |
| `test/src/lib/LibProdDeployV1.t.sol` | V1 creation bytecode matches constant |
| `test/src/lib/LibProdDeployV1V2.t.sol` | V1 and V2 codehashes are equal |
| `test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol` | Fork test: live beacon implementation address, code deployment, codehash, creation bytecode match |
| `test/src/concrete/deploy/StoxProdV2.t.sol` | Fork test: V2 address has code deployed |
| `test/lib/LibTestDeploy.sol` | Helper: deploys via Zoltu, asserts address matches `LibProdDeployV2.STOX_RECEIPT_VAULT` |

### Coverage Summary

| Coverage area | Status |
|---|---|
| Constructor disables initializers | COVERED |
| Bytecode / codehash integrity | COVERED (multiple test files) |
| Live on-chain address verification | COVERED (fork tests) |
| V1/V2 codehash equivalence | COVERED |
| Behavioral tests (initialize, certify, deposit, withdraw, etc.) | Not tested directly — all behavior is in ethgild parent |

---

## Findings

### A04-1 — INFO: No behavioral unit tests for StoxReceiptVault (inherited behavior)

**Severity:** INFO

**Description:**
`StoxReceiptVault` has no behavioral unit tests exercising `initialize`, `certify`, `confiscateShares`, `confiscateReceipt`, `redeposit`, `setAuthorizer`, or any ERC4626/ERC20 inherited functionality through a `StoxReceiptVault` instance.

This was previously raised as A04-3 (LOW) in the 2026-03-18-01 audit and **dismissed** by triage with the rationale: "all behavior is in ethgild OffchainAssetReceiptVault base; testing deps is out of scope." The ethgild library has extensive test coverage (24+ test files for `OffchainAssetReceiptVault` alone) exercising all the inherited functions.

Since the contract body is empty (zero overrides, zero new functions, zero new state), there is no stox-specific behavioral surface to test. The single existing test (`testConstructorDisablesInitializers`) correctly verifies the one security-critical property specific to this type: that the implementation contract cannot be initialized directly.

Downgraded from LOW to INFO to reflect the prior triage decision and the fact that the contract adds no new logic. If overrides are ever added to `StoxReceiptVault`, behavioral tests covering those overrides should be added at that time.

No fix file needed for INFO-level findings.
