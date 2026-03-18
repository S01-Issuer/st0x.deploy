# Pass 2: Test Coverage — StoxReceipt.sol

## Evidence of Thorough Reading

**Source file:** `src/concrete/StoxReceipt.sol` (11 lines)

- Contract: `StoxReceipt` (line 10) — empty body, inherits `Receipt` from `ethgild/concrete/receipt/Receipt.sol`

No functions, types, errors, events, or constants are defined in `StoxReceipt.sol` itself. All behavior is inherited from the base `Receipt` contract.

**Inherited `Receipt` contract** (`lib/ethgild/src/concrete/receipt/Receipt.sol`):

Struct:
- `Receipt7201Storage` (line 41): fields `manager` (`IReceiptManagerV2`), `sender` (`address`)

Constants (file-level):
- `RECEIPT_STORAGE_ID` (line 17): `"rain.storage.receipt.1"`
- `RECEIPT_STORAGE_LOCATION` (line 20): ERC-7201 storage slot `bytes32`
- `DATA_URI_BASE64_PREFIX` (line 23): `"data:application/json;base64,"`
- `RECEIPT_NAME_SUFFIX` (line 26): `" Receipt"`
- `RECEIPT_SYMBOL_SUFFIX` (line 29): `" RCPT"`

Functions (line numbers in `Receipt.sol`):
- `getStorageReceipt()` — private pure, line 47
- `_onlyManager()` — internal view, line 67
- `_withSenderBefore(address)` — internal, line 87
- `_withSenderAfter()` — internal, line 94
- `_msgSender()` — internal view override, line 100
- `initialize(bytes memory)` — public virtual initializer, line 109 (ICloneableV2 real initializer)
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

Errors:
- `OnlyManager` (imported from `ErrReceipt.sol`, used in `_onlyManager()`, line 71)
- `InitializeSignatureFn` (from `ICloneableV2` interface, line 13 of ICloneableV2.sol — but NOT implemented in Receipt)

## Coverage Analysis

### Is StoxReceipt instantiated or tested anywhere?

Yes, in two test files:

**`test/src/lib/LibProdDeployV2.t.sol`** — codehash and bytecode consistency tests:
- `testDeployAddressStoxReceipt()` (line 38): deploys via Zoltu factory, checks address and codehash match `LibProdDeployV2` constants.
- `testCodehashStoxReceipt()` (line 79): `new StoxReceipt()` and asserts codehash matches constant.
- `testCreationCodeStoxReceipt()` (line 108): asserts pointer creation code matches `type(StoxReceipt).creationCode`.
- `testRuntimeCodeStoxReceipt()` (line 134): `new StoxReceipt()` and asserts runtime code matches pointer constant.
- `testGeneratedAddressStoxReceipt()` (line 162): asserts pointer deployed address matches library constant.

**`test/src/lib/LibProdDeployV1V2.t.sol`**:
- `testStoxReceiptCodehashV1EqualsV2()` (line 17): asserts V1 and V2 codehash constants are equal (pure, no deployment).

**`test/src/concrete/deploy/StoxUnifiedDeployer.prod.base.t.sol`** (fork test):
- Checks `receiptImpl` address and codehash against live Base mainnet (lines 65–71).
- Checks creation bytecode matches compiled artifact (lines 86–89).

### Are inherited functions (from Receipt) tested in context?

**Not tested in isolation for StoxReceipt.** There is no test file for `StoxReceipt` as a behavioral unit. The tests above exclusively verify bytecode identity (codehash and creation code match). None of them:
- Call `initialize(bytes)` on a `StoxReceipt` instance and verify it succeeds or sets state.
- Call `initialize(bytes)` a second time to verify re-initialization is blocked.
- Call `manager()` on an initialized instance to verify it returns the expected manager.
- Call `managerMint`, `managerBurn`, `managerTransferFrom`, or `receiptInformation` on a `StoxReceipt` instance.
- Call any manager-gated function from a non-manager to verify `OnlyManager` is enforced.
- Call `name()`, `symbol()`, or `uri()` on an initialized `StoxReceipt` instance.

The inherited behaviors are exercised only through integration tests of the full system (fork tests), where `StoxReceipt` is a beacon proxy implementation and interacted with indirectly. Unit-level isolation tests for `StoxReceipt` are absent.

### Is the ICloneableV2 initialize pattern tested?

**The `initialize(bytes)` success path is not directly tested on StoxReceipt.** The `initialize(address)` typed overload that should always revert with `InitializeSignatureFn` is not implemented by `Receipt` (or `StoxReceipt`), and there are no tests checking for it.

For comparison, `StoxWrappedTokenVault` has:
- `testConstructorDisablesInitializers()` — verifies implementation is locked.
- `testInitializeAddressAlwaysReverts(address)` — verifies the typed `initialize(address)` overload reverts with `InitializeSignatureFn`.
- `testInitializeSuccess()` — verifies `initialize(bytes)` succeeds via beacon proxy.

None of these patterns exist for `StoxReceipt`.

The constructor calls `_disableInitializers()` (inherited from `Receipt`), so a direct call to `initialize(bytes)` on the implementation contract will revert — but this is not tested.

## Findings

### A03-P2-1: No behavioral unit tests for StoxReceipt [LOW]

There is no test file or test function that exercises `StoxReceipt` at the behavioral level. Existing tests only verify bytecode identity (codehash, creation code, runtime code). The following behaviors are untested in isolation:

1. `initialize(bytes)` success path on a proxy: sets `manager`, returns `ICLONEABLE_V2_SUCCESS`.
2. `initialize(bytes)` on the implementation (direct): reverts because `_disableInitializers()` is called in the constructor.
3. `initialize(bytes)` re-initialization on a proxy: reverts (OZ initializer guard).
4. `manager()` returns the address passed during initialization.
5. `managerMint` access control: non-manager caller reverts with `OnlyManager`.
6. `managerBurn` access control: non-manager caller reverts with `OnlyManager`.
7. `managerTransferFrom` access control: non-manager caller reverts with `OnlyManager`.
8. `receiptInformation` event emission: emits `ReceiptInformation` when data is non-empty; no-op when empty.
9. `name()` / `symbol()` output format: appends `" Receipt"` / `" RCPT"` to the vault share symbol.
10. `uri()` output: returns base64-encoded JSON data URI.

The absence of unit tests means regressions in any of these behaviors would not be caught by the test suite without fork tests running against a pinned block.

**Severity:** LOW

**Fix file:** `.fixes/A03-P2-1.md`

### A03-P2-2: initialize(address) typed overload not tested (and not implemented) [INFO]

The `ICloneableV2` interface recommends a typed `initialize(address)` overload that always reverts with `InitializeSignatureFn`. Neither `Receipt` nor `StoxReceipt` implements this overload. This was flagged as `A03-1` in Pass 1 (INFO). From a test coverage perspective, there are also no tests verifying the absence or presence of this behavior. This is informational because there is no test gap for behavior that does not exist — but if the overload were added as a fix to A03-1, tests would also be needed.

**Severity:** INFO (dependent on Pass 1 finding A03-1 being addressed first)
