# Integration Guide — st0x Corporate Actions Tokens

This document is for **external protocols and indexers** integrating with st0x
vault tokens. It covers the non-standard behaviors introduced by the
corporate-actions system (stock splits via lazy rebase migration) and the admin
capabilities baked into the RWA compliance model.

If you're developing on the vault itself, see `CLAUDE.md` for build instructions
and `CORPORATE-ACTIONS-SPEC.md` for the as-built specification.

## Rebasing Behavior (The Most Important Section)

Both `StoxReceiptVault` (ERC-20 shares) and `StoxReceipt` (ERC-1155 receipts)
are **rebasing tokens**. When a stock split lands, every holder's `balanceOf`
changes without a `Transfer` event.

### What happens

1. An authorized scheduler calls
   `scheduleCorporateAction(typeHash,
   effectiveTime, parameters)` on the
   vault (via the diamond facet).
2. When `block.timestamp >= effectiveTime`, the split is "in effect." No
   on-chain transaction is needed for this — time simply passes.
3. From this point, `balanceOf(account)` and `totalSupply()` return the
   **rebased** values (original × multiplier), even though the stored balances
   haven't been rewritten yet.
4. The first transaction that touches any account (transfer, mint, burn)
   triggers **lazy migration** inside `_update`: the account's stored balance is
   rasterized to the post-split value and written directly to storage.

### What this means for integrators

**Do not cache `balanceOf` across blocks.** It can change between any two calls
without a `Transfer` event if a split's effective time passes in between.

**Do not compute balances from `Transfer` events alone.** Event-sourced indexers
that sum `Transfer` events will diverge from `balanceOf` after a split. You need
to supplement with one or both of:

- `CorporateActionEffective(uint256 indexed actionIndex, uint256
  actionType, uint64 wasEffectiveAt)`
  — emitted the first time any transaction touches the vault after a split
  becomes effective. Fires **before** any per-account migration in the same
  transaction. Use this as a trigger to poll `balanceOf` for all tracked
  accounts.
- `AccountMigrated(address indexed account, uint256 fromCursor, uint256
  toCursor, uint256 oldBalance, uint256 newBalance)`
  — emitted per account when its stored balance is actually rasterized (on first
  touch post-split). Not emitted for zero-balance accounts.
- `ReceiptAccountMigrated(address indexed account, uint256 indexed id,
  uint256 fromCursor, uint256 toCursor, uint256 oldBalance, uint256
  newBalance)`
  — same, for ERC-1155 receipt balances.

**`wasEffectiveAt` is almost always in the past.** It records when the split was
_scheduled_ to take effect, not when the first transaction observed it. The gap
is however many blocks elapsed between `effectiveTime` and the first
post-effectiveTime transaction.

**Use `convertToAssets` on the ERC-4626 wrapper** rather than computing share
value from `totalSupply()`. The wrapper captures rebases in share price, so its
`convertToAssets` method always reflects the post-rebase underlying value
without the caller needing to know about splits.

### Transfer-time rebase (subtle)

When a transfer touches an account that hasn't been migrated yet, the migration
happens inside `_update` before the transfer amount is moved. This means:

```
// Alice has 100 raw shares, a 2× split has landed (not yet migrated).
// Bob has 0 shares.
alice.transfer(bob, 50);

// Alice: raw 100 → migrated to 200 → minus 50 = 150
// Bob: raw 0 → migrated to 0 → plus 50 = 50
```

An integrator checking `balanceAfter(alice) - balanceBefore(alice)` will see
`150 - 100 = +50` (but alice sent 50, so they'd expect `-50`). The `+100` from
migration offsets the `-50` from the transfer. This is not a bug — it's the
correct lazy-migration behavior. But it means **balance deltas around a transfer
include both the transfer amount and any pending rebase**.

**Recommendation:** Check the `AccountMigrated` event in the same transaction to
separate the rebase delta from the transfer delta.

## Stock Split Magnitude

Stock splits are expected to be in the range **1/100× to 100×** per action. The
system enforces bounds of `trunc(1e18 * multiplier) ∈ [1,
1e36]` — a much wider
ceiling designed for safety rather than operational use. In practice, the
multi-sig scheduler will stay within the real-world range (2× to 10× for forward
splits, 1/2× to 1/10× for reverse splits).

There is no limit on the number of splits that can accumulate; each one
compounds on the previous. Multiple pending splits at different future effective
times are possible.

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
