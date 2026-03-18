# Pass 1: Security — StoxReceipt.sol

## Evidence of Thorough Reading

**Contract defined in `src/concrete/StoxReceipt.sol`:**

- `StoxReceipt` (line 10) — empty body, inherits `Receipt` from `ethgild/concrete/receipt/Receipt.sol`

No functions, types, errors, events, or constants are defined in `StoxReceipt.sol` itself. All behavior is inherited from the base `Receipt` contract.

**Inherited `Receipt` contract (lib/ethgild/src/concrete/receipt/Receipt.sol) — read for context:**

Types/structs:
- `Receipt7201Storage` (struct, line 41): fields `manager` (`IReceiptManagerV2`) and `sender` (`address`)

Constants:
- `RECEIPT_STORAGE_ID` (line 17): `"rain.storage.receipt.1"`
- `RECEIPT_STORAGE_LOCATION` (line 20): `bytes32` ERC-7201 slot
- `DATA_URI_BASE64_PREFIX` (line 23): `"data:application/json;base64,"`
- `RECEIPT_NAME_SUFFIX` (line 26): `" Receipt"`
- `RECEIPT_SYMBOL_SUFFIX` (line 29): `" RCPT"`

Functions (with line numbers in `Receipt.sol`):
- `getStorageReceipt()` — private pure, line 47
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

Errors (imported from `ErrReceipt.sol`):
- `OnlyManager` (line 10 import, used line 71)

Interface errors (from `ICloneableV2`):
- `InitializeSignatureFn` (defined in interface, line 13 of ICloneableV2.sol)

## Findings

### A03-1: Missing `initialize(address)` typed overload that reverts with `InitializeSignatureFn` [INFO]

The `ICloneableV2` interface specification (see `ICloneableV2.sol` lines 28–36) states:

> It is RECOMMENDED that the `ICloneableV2` contract implements a typed `initialize` function that overloads the generic `initialize(bytes)` function. This overloaded function MUST revert with `InitializeSignatureFn` always, so that it is NEVER accidentally called.

Neither the base `Receipt` contract nor `StoxReceipt` implements `initialize(address)` that reverts with `InitializeSignatureFn`. The `CLAUDE.md` project guidance documents this as a required pattern: "initialize(address) always reverts (documents signature)".

Other contracts in this codebase (e.g. `StoxWrappedTokenVault`) do implement this typed overload. `StoxReceipt` (via `Receipt`) is missing it.

**Impact:** There is no exploitable path here — `initialize(bytes memory data)` is the real initializer and is protected by the `initializer` modifier from OpenZeppelin. However, the absence of the typed overload means tooling and developers may accidentally encode calldata for the wrong signature without a clear revert, violating the documented ICloneableV2 contract and making the interface inconsistent with the rest of the codebase.

**Severity:** INFO
