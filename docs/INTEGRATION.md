# Integration Guide — st0x Corporate Actions Tokens

This document is for **external protocols and indexers** integrating with st0x
vault tokens. It covers the non-standard behaviors introduced by the
corporate-actions system (stock splits via lazy rebase migration) and the admin
capabilities baked into the RWA compliance model.

If you're developing on the vault itself, see `CLAUDE.md` for build instructions
and `CORPORATE-ACTIONS-SPEC.md` for the as-built specification.

## Admin Capabilities

The st0x vault implements an RWA (Real World Asset) compliance model. External
integrators should be aware of the following centralized capabilities:

| Capability                   | Trigger                            | Effect                                                       |
| ---------------------------- | ---------------------------------- | ------------------------------------------------------------ |
| **Beacon upgrade**           | Beacon owner (multi-sig)           | Can replace all token logic at any time                      |
| **Authorizer swap**          | Vault owner                        | Can change which addresses are allowed to transfer           |
| **Certification freeze**     | Certifier role                     | Halts all transfers when `certifiedUntil` expires            |
| **Confiscation**             | Confiscator role                   | Seizes shares or receipts from any address (bypasses freeze) |
| **Stock split scheduling**   | `SCHEDULE_CORPORATE_ACTION` holder | Multiplies all balances at a future time                     |
| **Stock split cancellation** | `CANCEL_CORPORATE_ACTION` holder   | Removes a pending split before effective time                |

**For lending protocols / AMMs:** Your pool can be frozen at any time via the
certification mechanism, and individual addresses can be blocklisted via the
authorizer. Evaluate whether your protocol can tolerate a temporary inability to
move the position.

**For custodians:** The confiscation capability means the vault operator can
seize assets. This is a regulatory requirement for RWA tokenization but should
be disclosed to end users.

## Decimals

`StoxReceiptVault.decimals()` inherits from the underlying asset:

- Wrapping USDC → 6 decimals
- Wrapping DAI → 18 decimals
- Other assets → whatever `asset.decimals()` returns

Do not hardcode 18.

## Querying Corporate Action State

The vault exposes stock split state through `ICorporateActionsV1`:

```solidity
// Get the most recent completed stock split.
(uint256 cursor, uint256 actionType, uint64 effectiveTime)
    = vault.latestActionOfType(ACTION_TYPE_STOCK_SPLIT, CompletionFilter.COMPLETED);

// Walk backward through all completed splits.
while (cursor != 0) {
    bytes memory params = vault.getActionParameters(cursor);
    Float multiplier = abi.decode(params, (Float));
    // ... process the split ...
    (cursor, actionType, effectiveTime)
        = vault.prevOfType(cursor, ACTION_TYPE_STOCK_SPLIT, CompletionFilter.COMPLETED);
}

// Check for pending (future) splits.
(cursor, actionType, effectiveTime)
    = vault.latestActionOfType(ACTION_TYPE_STOCK_SPLIT, CompletionFilter.PENDING);
```

## ERC-1155 Receipt Batch Reads

Both `balanceOf(account, id)` and `balanceOfBatch(accounts, ids)` on
`StoxReceipt` return rebased values. They are consistent with each other — a
batch read returns the same values as calling `balanceOf` per element.

## Contact

For integration support or to report security issues, see the repo's
`SECURITY.md` or contact the team via the channels listed in `README.md`.
