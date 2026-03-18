# Pass 3: Documentation — StoxReceipt.sol

## Evidence of Thorough Reading

**Source file:** `src/concrete/StoxReceipt.sol` (11 lines)

### Contract defined in StoxReceipt.sol

- `StoxReceipt` (line 10) — empty body, inherits `Receipt` from `ethgild/concrete/receipt/Receipt.sol`

No functions, types, errors, events, or constants are defined in `StoxReceipt.sol` itself. All behavior is inherited from the base `Receipt` contract.

### Base Receipt contract (lib/ethgild/src/concrete/receipt/Receipt.sol) — read for full context

**Struct:**
- `Receipt7201Storage` (line 41): fields `manager` (`IReceiptManagerV2`), `sender` (`address`)

**Constants (file-level):**
- `RECEIPT_STORAGE_ID` (line 17): `"rain.storage.receipt.1"`
- `RECEIPT_STORAGE_LOCATION` (line 20): ERC-7201 storage slot `bytes32`
- `DATA_URI_BASE64_PREFIX` (line 23): `"data:application/json;base64,"`
- `RECEIPT_NAME_SUFFIX` (line 26): `" Receipt"`
- `RECEIPT_SYMBOL_SUFFIX` (line 29): `" RCPT"`

**Functions (line numbers in Receipt.sol):**
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

**Errors:**
- `OnlyManager` (imported from `ErrReceipt.sol`, used line 71)

---

## Documentation Review

### NatSpec present?

Yes. `StoxReceipt.sol` has two NatSpec lines:

```solidity
/// @title StoxReceipt
/// @notice A Receipt specialized for Stox. Currently there are no modifications
/// to the base contract, but this is here to prepare for any future upgrades.
```

For a contract that is entirely empty body (no additional functions, no overrides, no state), this is the only documentation level that applies. There is no function-level or parameter-level NatSpec to add within the file itself.

### Is the purpose documented?

Yes. The `@notice` explains:
1. What it is: a Receipt specialized for Stox.
2. Current state: no modifications to the base contract.
3. Reason for existence: future upgrade preparedness.

This is accurate and sufficient for a pure delegation contract.

### Are there misleading or missing doc comments?

**Missing: reference to the base contract.** The `@notice` says "no modifications to the base contract" without naming or linking to it. A reader seeing this contract in isolation cannot locate the base without reading the import on line 5. A `@dev` tag pointing to `ethgild/concrete/receipt/Receipt.sol` and a brief description of what `Receipt` does would improve navigability.

**Missing: ICloneableV2 initialization data encoding.** `Receipt.initialize(bytes memory data)` decodes `data` as `abi.decode(data, (address))` — the manager address. This is not documented in `StoxReceipt.sol`. Any integrator relying solely on `StoxReceipt.sol` as the entry-point file would need to dig into `Receipt.sol` to discover the initialization data format. A `@dev` note documenting the ABI encoding of `initialize` data would be consistent with documentation in other contracts (e.g., `StoxWrappedTokenVault` documents its `initialize` encoding in the NatSpec).

**Not misleading.** The existing `@notice` is accurate. The claim that there are "no modifications" is correct — the contract is entirely empty body. The forward-looking statement about "future upgrades" is standard pattern documentation and not misleading.

---

## Findings

### A03-P3-1: Missing `@dev` note naming the base contract and its initialization data encoding [LOW]

`StoxReceipt.sol` documents itself with `@title` and `@notice` only. For a contract that is a pure delegation to `Receipt`, this is marginally sufficient for a reader who inspects the imports, but:

1. There is no `@dev` tag cross-referencing `ethgild/concrete/receipt/Receipt.sol`, forcing readers to parse the import rather than the documentation.
2. There is no documentation of the `initialize(bytes memory data)` ABI encoding. `Receipt.initialize` decodes `data` as `abi.decode(data, (address))` (the manager address), but this is undocumented from the `StoxReceipt` perspective. All other ICloneableV2 contracts in this codebase that accept initialization data document the encoding.

Other contracts in this codebase (e.g. `StoxWrappedTokenVault`) document the `initialize` data format in NatSpec. Omitting it from `StoxReceipt` creates an inconsistency and a discoverability gap for integrators.

**Severity:** LOW

**Fix file:** `.fixes/A03-P3-1.md`
