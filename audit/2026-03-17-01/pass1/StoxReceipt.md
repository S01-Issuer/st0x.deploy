# Pass 1: Security — A02: StoxReceipt.sol

## Evidence of Thorough Reading

**File:** `src/concrete/StoxReceipt.sol` (10 lines)

- **Contract:** `StoxReceipt` (line 10)
- **Functions:** None (empty body)
- **Types/Errors/Constants:** None
- **Inheritance:** `Receipt` from `ethgild/concrete/receipt/Receipt.sol`

The contract body is `{}` — completely empty. It inherits all logic from `Receipt`.

### Parent `Receipt` inherited surface (reviewed)

Key functions in `Receipt.sol`: `getStorageReceipt` (47), constructor (55), `onlyManager` modifier (60), `_onlyManager` (67), `withSender` modifier (78), `_withSenderBefore` (87), `_withSenderAfter` (94), `_msgSender` (100), `initialize` (109), `uri` (123), `name` (143), `symbol` (148), `_vaultShareSymbol` (155), `_vaultAssetSymbol` (163), `_vaultDecimals` (169), `manager` (175), `managerMint` (181), `managerBurn` (192), `managerTransferFrom` (203), `_update` (217), `_receiptInformation` (232), `receiptInformation` (240).

### Security checklist — all clear

1. **Input validation** — No new inputs; parent validates via `abi.decode` in `initialize`.
2. **Access controls** — `onlyManager` modifier with custom error `OnlyManager()` guards all privileged operations.
3. **Reentrancy** — `withSender` modifier correctly sets/clears transient sender around ERC1155 callbacks.
4. **Arithmetic** — Solidity 0.8.25 built-in checks; no `unchecked` blocks.
5. **Error handling** — Custom errors only; no string reverts.
6. **Storage** — ERC-7201 namespaced storage; `_disableInitializers()` in constructor.

## Findings

No findings.
