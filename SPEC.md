<!-- SPDX-License-Identifier: LicenseRef-DCL-1.0 -->
<!-- SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd -->

# st0x Corporate Action Registry — Spec

## Overview

tStock tokens need to handle corporate actions — name/symbol changes, stock
splits, reverse splits, cash dividends, stock dividends. The corporate action
registry is the onchain governance/dispatch layer that makes this possible.

The registry is not just an event log. It's onchain readable state — other
contracts (lending protocols, oracles, strategies) can query it to reason about
upcoming and in-progress corporate actions and adjust behaviour accordingly.
This is critical for composability: downstream protocols can make independent
risk decisions without offchain coordination.

## Why

- 1:1 parity between offchain shares and onchain tokens is a core design goal
- Corporate actions introduce information asymmetry between offchain and onchain
  — the registry makes this observable
- Without onchain signalling, protocols operating across a corporate action
  window are exposed to adverse selection
- Corporate-action-aware transfers and mints/burns prevent stale-state execution

Note: the wrapper contract (`StoxWrappedTokenVault` in st0x.deploy) is not part
of this architecture. It wraps the underlying receipt vault token for DeFi
compatibility and captures revaluations in price rather than supply. It
automatically picks up name/symbol changes from the underlying.

## Contract Hierarchy

### Current

```
StoxWrappedTokenVault (ERC-4626 — NOT part of this spec)
    └── StoxReceiptVault (extends OffchainAssetReceiptVault)
            └── OffchainAssetReceiptVault (ethgild — base vault with authoriser pattern)
    └── StoxReceipt (extends Receipt)
            └── Receipt (ethgild — ERC-1155 receipts)

OffchainAssetReceiptVaultAuthorizerV1 (RBAC authoriser)
    Permissions: CERTIFY, DEPOSIT, WITHDRAW, CONFISCATE_SHARES, CONFISCATE_RECEIPT,
                 TRANSFER_SHARES, TRANSFER_RECEIPT
    Each permission has a corresponding ADMIN role
    Vault calls authorizer.authorize(user, permission, data) before sensitive state changes
```

**Important**: all new corporate action logic lives at the st0x layer
(`StoxReceiptVault`, `StoxReceipt`). The ethgild/rain.vats layer
(`OffchainAssetReceiptVault`, `Receipt`) is not modified.

## Registry Architecture

### Design Principles

- **Token-agnostic** — single registry contract, token address passed at
  dispatch time
- **Onchain readable state** — not just events. Other contracts can query action
  type, state, params, timing. This is the key difference from a simple event
  log
- **Namespaced Corporate Action ID per token** — type/number (e.g. SPLIT/1,
  SPLIT/2, NAME_SYMBOL/1). Prevents ID clashes across action types or if
  registry is ever replaced
- **Action lifecycle** — SCHEDULED (pending, observable) → IN_PROGRESS →
  COMPLETE
- **Effective timestamps** — actions scheduled in advance. Pending before
  effective time, executable after
- **Append-only** — once recorded, can't be changed

### Why Onchain Readable State Matters

Corporate actions create information asymmetry. Offchain participants know about
an upcoming split immediately and reprice; onchain protocols have no inherent
awareness unless it's signalled onchain.

By exposing action type, timing, and state as readable contract storage:
- Protocols sensitive to inventory exposure can pause or adjust when a SCHEDULED
  action exists
- Pricing protocols can verify their oracle's Corporate Action ID matches the
  token's
- Lending protocols can adjust collateral ratios ahead of a split
- Strategies can halt trading during the transition window

Events alone don't give contracts this ability — they can't be read onchain.

### CAID: Token Hashes on Receipt

The registry passes its raw ID (actionType, number) to the token. The token
hashes `msg.sender` (the registry address) with the ID to produce the CAID:

```solidity
function _computeCAID(bytes32 actionType, uint256 number) internal view returns (bytes32) {
    return keccak256(abi.encodePacked(msg.sender, actionType, number));
}
```

This way:
- The token controls how the CAID is derived — no trust in the registry to hash
  correctly
- If the registry is ever replaced via the owner/authoriser pattern, old IDs
  from a previous registry can't collide (different `msg.sender`)
- The token doesn't hardcode a single registry — it trusts whoever the
  authoriser says can call its corporate action functions

### Corporate-Action-Aware Transfers

Standard ERC-20 transfers have no notion of expected global state. A transaction
signed before a split could execute after it, with different economic meaning:

```solidity
function transferCA(address to, uint256 amount, bytes32 expectedCAID) external {
    require(_currentCAID == expectedCAID, "CAID mismatch");
    transfer(to, amount);
}
```

If the CAID doesn't match, the transfer reverts. Safety-aware integrations opt
in; standard `transfer()` continues to work for naive integrations.

Same pattern for mint and burn — callers specify expected CAID to prevent
stale-state execution at the onchain/offchain boundary.

### Authoriser Integration

New permissions added alongside existing ones:

```solidity
bytes32 constant UPDATE_NAME_SYMBOL = keccak256("UPDATE_NAME_SYMBOL");
bytes32 constant REBASE = keccak256("REBASE");
```

With corresponding admin roles in the authoriser. The registry contract gets
granted these roles. Same authoriser, same RBAC pattern — no new permission
model.

---

## Name/Symbol Updates

### Changes to StoxReceiptVault

- Name/symbol override storage with ERC-7201 namespaced slots
- `name()` / `symbol()` overrides that fall through to base when no override set
- `updateNameSymbol()` gated by authoriser (`UPDATE_NAME_SYMBOL` permission)
- CAID stored locally after each corporate action update
- Wrapper (`StoxWrappedTokenVault`) automatically reflects new name/symbol

---

## Rebasing (Stock Splits / Reverse Splits)

### Problem

A 3:1 stock split means offchain share count triples but onchain doesn't.
Breaks 1:1 parity. After a split, 1 offchain share must equal 1 onchain token.

### Multiplier Storage

Numerator/denominator pair for exactness. 3:1 split = `{3, 1}`. 1:3 reverse
split = `{1, 3}`. Clean integer ratios, no precision loss.

### Reads

Apply all multipliers **sequentially** from user's `lastRebasedVersion` to
`rebaseVersion`:

```
balance = rawBalance
for v in (user.lastRebasedVersion + 1) .. rebaseVersion:
    balance = balance * multipliers[v].numerator / multipliers[v].denominator
return balance
```

Sequential application matters because of rounding. Applying `1/3` then `3x`
then `1/3` then `3x` does NOT equal a single `1x` multiplier due to integer
rounding at each step.

### Writes (Rasterize-Then-Update)

1. **Read** current balance (applying pending multipliers)
2. **Store** rasterized balance as new raw balance
3. **Update** `lastRebasedVersion` to `rebaseVersion`
4. **Apply** the actual increment/decrement

User input is never scaled. Sending 1 share sends exactly 1 — not 0.999999...
Rasterization happens before transfer math.

### Lazy Migration

- Migration happens **lazily** on next interaction (send, receive, any balance
  touch)
- Gas cost is **one-time per user** — proportional to pending multipliers
- After migration, zero overhead — standard ERC-20 cost
- **Both sender and recipient** rasterized on transfer
- Corporate actions rare (~1-2/year/stock), accumulated multipliers stay small

### New Mints

Post-rasterization, 1 = 1 for new mints. Newly minted token after a 3:1 split
represents 1 post-split share. Same as offchain. This is the whole point.

### Price Synchronisation

Oracle price updates must include the current Corporate Action ID. Consumers
verify oracle CAID matches onchain CAID. This ensures prices transition
atomically with supply changes.

### ERC-1155 Receipt Rebasing (StoxReceipt)

Vault receipts must also rebase. 100 tCOIN deposited pre-split becomes 300 post
3:1. Same multiplier mapping and lazy migration in `StoxReceipt`.

### Total Supply

Eagerly updated on each corporate action (single storage slot, no per-user
concern).

---

## Future Action Types

The registry architecture supports:
- **Cash dividends** — distribution contract, Merkle tree of entitlements,
  pull-based claims in stablecoin. No rebase or supply change.
- **Stock dividends** — same Merkle/pull pattern, distributing additional ERC-20
  tokens representing new shares. Not a rebase.

These use the same Corporate Action ID and registry lifecycle but different
execution paths.

---

## Gas Considerations

- **Name/symbol**: single SSTORE per field — trivial
- **Rebase dispatch**: single SSTORE for multiplier + version increment —
  trivial
- **Lazy migration**: proportional to pending multipliers per user. ~1-2
  corporate actions/year, so minimal
- **Batch rasterization**: public `rasterize(address[])` for keeper bots or
  pre-migration before pool operations

## Security

- Actions gated by existing authoriser RBAC — same pattern as DEPOSIT, WITHDRAW,
  CERTIFY
- Registry upgradeable (governance wrapper) — new actions, safeguards, controls
  can be added over time
- Upgrade authority subject to multisig and role-based controls, distinct from
  bridge automation
- Multipliers append-only
- Rasterization idempotent
- TimelockController for corporate action roles (aligns with Steakhouse DD
  requirements)

## Open Questions

1. **Fractional share handling** — reverse split creates fractional balances?
   Round down and track dust? Cash-in-lieu via separate dividend?
2. **ERC-1155 receipt rasterization** — same `_update` hook pattern in
   StoxReceipt?
3. **Historical balance queries** — need `balanceOfAtVersion(address, uint256)`
   for analytics?
4. **Batch rasterization incentives** — gas refund for rasterizing stale
   accounts?
5. **Registry deployment** — factory deploys registry alongside vault, or
   standalone?
6. **Governance over dispatch** — who can call `registry.schedule()`? Separate
   from who has roles in authoriser?
7. **Mempool protection** — standard transfers execute under new state, CA-aware
   transfers revert on mismatch. Is this the right default behaviour split?
