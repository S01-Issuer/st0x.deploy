# Pass 2 (Test Coverage) — StoxReceipt.sol

**Agent:** A03
**Source file:** `src/concrete/StoxReceipt.sol`
**Test file:** `test/src/concrete/StoxReceipt.t.sol`

## Evidence of Thorough Reading

### Source file: `src/concrete/StoxReceipt.sol` (12 lines)

- **License:** `LicenseRef-DCL-1.0` (line 1)
- **Pragma:** `=0.8.25` (line 3)
- **Import:** `Receipt` from `ethgild/concrete/receipt/Receipt.sol` (line 5)
- **Contract:** `StoxReceipt is Receipt` (line 12) — empty body, no functions/types/errors/constants defined

**Inherited from `Receipt` (lib/ethgild/src/concrete/receipt/Receipt.sol, 243 lines):**

Types:
- `Receipt7201Storage` struct (line 41): fields `manager` (`IReceiptManagerV2`), `sender` (`address`)

Constants (file-level):
- `RECEIPT_STORAGE_ID` (line 17): `"rain.storage.receipt.1"`
- `RECEIPT_STORAGE_LOCATION` (line 20): ERC-7201 bytes32 slot
- `DATA_URI_BASE64_PREFIX` (line 23): `"data:application/json;base64,"`
- `RECEIPT_NAME_SUFFIX` (line 26): `" Receipt"`
- `RECEIPT_SYMBOL_SUFFIX` (line 29): `" RCPT"`

Errors (imported):
- `OnlyManager` (from `ErrReceipt.sol`, used at line 71)

Functions:
- `getStorageReceipt()` — private pure, line 47
- constructor — line 55, calls `_disableInitializers()`
- `_onlyManager()` — internal view, line 67
- `_withSenderBefore(address)` — internal, line 87
- `_withSenderAfter()` — internal, line 94
- `_msgSender()` — internal view override, line 100
- `initialize(bytes memory)` — public virtual initializer, line 109
- `uri(uint256)` — public view virtual override, line 123
- `name()` — public view virtual, line 143
- `symbol()` — external view virtual, line 148
- `_vaultShareSymbol()` — internal view virtual, line 155
- `_vaultAssetSymbol()` — internal view virtual, line 163
- `_vaultDecimals()` — internal view virtual, line 169
- `manager()` — external view virtual, line 175
- `managerMint(address,address,uint256,uint256,bytes)` — external virtual, line 181
- `managerBurn(address,address,uint256,uint256,bytes)` — external virtual, line 192
- `managerTransferFrom(address,address,address,uint256,uint256,bytes)` — external virtual, line 203
- `_update(address,address,uint256[],uint256[])` — internal virtual override, line 217
- `_receiptInformation(address,uint256,bytes)` — internal virtual, line 232
- `receiptInformation(uint256,bytes)` — external virtual, line 240

### Test file: `test/src/concrete/StoxReceipt.t.sol` (16 lines)

- **License:** `LicenseRef-DCL-1.0` (line 1)
- **Pragma:** `=0.8.25` (line 3)
- **Imports:** `Test` (forge-std), `StoxReceipt`, `Initializable` (line 5-7)
- **Contract:** `StoxReceiptTest is Test` (line 9)
- **Functions:**
  - `testConstructorDisablesInitializers()` — external, line 11

## Coverage Analysis

### What the test file covers

The single test `testConstructorDisablesInitializers` (line 11) deploys a `StoxReceipt` implementation via `new StoxReceipt()` and verifies that calling `initialize(abi.encode(address(1)))` on it reverts with `Initializable.InvalidInitialization`. This confirms the constructor's `_disableInitializers()` call works.

### What is NOT covered

The following inherited behaviors have zero unit-test coverage on `StoxReceipt` instances:

1. **`initialize(bytes)` success path via proxy** — no test creates a proxy, calls `initialize`, and asserts `ICLONEABLE_V2_SUCCESS` is returned.
2. **`initialize(bytes)` re-initialization guard** — no test verifies that a second `initialize` call on an already-initialized proxy reverts.
3. **`manager()` after init** — no test asserts `manager()` returns the address passed during initialization.
4. **`managerMint` access control** — no test verifies non-manager callers revert with `OnlyManager`.
5. **`managerMint` success path** — no test mints via manager and checks balance.
6. **`managerBurn` access control** — no test verifies non-manager callers revert with `OnlyManager`.
7. **`managerBurn` success path** — no test burns via manager and checks balance goes to zero.
8. **`managerTransferFrom` access control** — no test verifies non-manager callers revert with `OnlyManager`.
9. **`receiptInformation` event emission** — no test checks `ReceiptInformation` is emitted for non-empty data.
10. **`receiptInformation` no-op** — no test checks no event is emitted for empty data.
11. **`name()` format** — no test verifies `"<symbol> Receipt"` output.
12. **`symbol()` format** — no test verifies `"<symbol> RCPT"` output.
13. **`uri()` output** — no test verifies data URI prefix or JSON structure.

### Upstream coverage

The ethgild repo has extensive tests for `Receipt` directly (`lib/ethgild/test/src/concrete/receipt/Receipt.t.sol`), covering: initialize, managerMint (success + revert), managerBurn (success + revert + insufficient balance), managerTransferFrom (success + revert + unauthorized + self-transfer), balanceOf, balanceOfBatch, setApprovalForAll/isApprovedForAll, safeTransferFrom, and safeBatchTransferFrom. These tests exercise the base `Receipt` contract, not `StoxReceipt`.

### Assessment

Since `StoxReceipt` is an empty wrapper (`contract StoxReceipt is Receipt {}`), it inherits all behavior identically from `Receipt`. The upstream ethgild test suite provides thorough behavioral coverage of the `Receipt` contract. The key question is whether the Stox project needs to re-test all inherited behaviors on `StoxReceipt` specifically.

The current test covers the one thing that is unique to the deployment context: that the implementation contract cannot be initialized directly. The remaining behaviors are tested upstream and exercised in integration via fork tests.

## Findings

### A03-1 [LOW] — Incomplete implementation of previously proposed behavioral tests

The previous audit (2026-03-18-01) identified the lack of behavioral unit tests as A03-P2-1 (LOW) and proposed a comprehensive fix in `.fixes/A03-P2-1.md` containing 14 test functions. During triage, only one test was implemented (`testConstructorDisablesInitializers`). The remaining 13 proposed tests were not added.

While `StoxReceipt` is an empty wrapper and upstream tests cover `Receipt` behavior, the partial implementation of the proposed fix leaves the following gaps:

- `initialize(bytes)` success and re-initialization guard on a `StoxReceipt` proxy
- `manager()` post-initialization state verification
- Access control (`OnlyManager`) enforcement on `managerMint`, `managerBurn`, `managerTransferFrom`
- `managerMint`/`managerBurn` success paths with balance assertions
- `receiptInformation` event emission behavior
- `name()`/`symbol()`/`uri()` output format

If `StoxReceipt` ever adds overrides or modifications, there would be no regression safety net specific to the `StoxReceipt` type. The constructor test alone does not confirm that the contract initializes and behaves correctly when deployed as a proxy.

**Severity:** LOW — Behavioral risk is mitigated by upstream ethgild tests and fork tests, but direct coverage of `StoxReceipt` through a proxy is absent.

**Fix:** `.fixes/A03-1.md`

### A03-2 [INFO] — Mock contract inlined in proposed fix rather than in test/concrete/

The previous fix proposal (`.fixes/A03-P2-1.md`) included a `MockReceiptManager` contract inlined in the test file. Per project conventions (`CLAUDE.md`), test helper contracts should go in `test/concrete/` and test libraries in `test/lib/`. If the behavioral tests from A03-1 are implemented, the mock manager should be placed in `test/concrete/MockReceiptManager.sol`.

**Severity:** INFO — Style/convention only. Only relevant if A03-1 is addressed.
