# Corporate Actions Specification

## Overview

A corporate action like a stock split must adjust the balance of every token holder simultaneously. Iterating over all holders in a single transaction is impossible at scale, so the system needs a mechanism that achieves the economic effect of a simultaneous adjustment without actually touching every account.

This specification describes five components that together solve this problem. Each component builds on the one before it: the diamond facet provides the architectural foundation, the doubly linked list provides the ordered data structure, action types define the triggers and their parameters, the rebase system implements the actual balance adjustments, and the query interface exposes state to external contracts.

## Design Principles

### Framework Principles

**Single source of truth.** All corporate action state lives on the vault itself. External contracts already depend on the vault address for balance queries — they should not need to discover or trust a separate registry.

**No manual execution.** Corporate actions take effect automatically when their effective time passes. No one needs to call a function to "execute" an action — the system detects that an action's time has arrived during normal contract interactions and applies it. This eliminates single-point-of-failure risk from requiring an operator to pull a trigger, and removes timezone/availability concerns for globally distributed teams.

**Extensibility without migration.** The framework must support future corporate action types (dividends, name changes, mergers) without storage migrations or vault redeployment. A versioned interface (`ICorporateActionsV1`) ensures external consumers can depend on a stable API while the implementation evolves behind it.

### Rebase Principles

**Sequential precision over mathematical equivalence.** Applying multipliers 1/3, 3, 1/3, 3 sequentially to 100 yields 99.999... due to accumulated rounding. Collapsing them into a single 1× multiplier yields exactly 100. The system must preserve the sequential result. This is not a bug — it is a deliberate choice that guarantees every account gets identical results regardless of when they interact with the contract. An account that transferred after every corporate action and an account that was dormant for a year must arrive at the same balance when they finally transact.

**Rasterize on write, never scale input.** When a user says "transfer 1 share," that means 1 share in current terms. The system must materialize (rasterize) the effective balance from stored base balance plus pending multipliers before applying any operation. Attempting to reverse-engineer a base amount from a current-terms input introduces additional precision errors and breaks user expectations.

**Migration is invisible.** Account holders should never need to call a separate "migrate" function. Migration happens automatically as a pre-step to any balance-changing operation (transfer, mint, burn) via the `_update` hook.

## Component 1: Diamond Facet Foundation

### Problem

Corporate actions require substantial logic — scheduling, data structures, multiplier storage, migration tracking, query interfaces. Adding this directly to the vault would exceed contract size limits. But the vault address must remain the single point of contact for external systems.

### Solution

A diamond facet delegates corporate action logic to a separate contract while preserving the vault's address as the entry point. The facet's storage lives in the vault's storage space using a collision-resistant slot (ERC-7201 namespaced storage), consistent with the vault's existing storage patterns.

The facet exposes its functionality through a versioned interface (`ICorporateActionsV1`). External consumers — oracles, lending protocols, wrapper contracts — import the interface rather than the concrete facet. The interface can be versioned independently of the implementation, and the vault itself can implement the same interface via delegatecall, so callers don't need to know whether they're hitting the facet directly or through the vault.

The facet needs its own authorization integration. Scheduling a corporate action and cancelling one are distinct privileges that can be assigned to different roles.

## Component 2: Doubly Linked List and Action Lifecycle

### Problem

Corporate actions must be ordered by time. An action scheduled for next month and an action scheduled for next week need to be applied in the right order regardless of when they were created. The system also needs to distinguish between actions that have taken effect (historical, immutable) and actions that are still pending (future, cancellable).

A simple sequential array doesn't work because actions might be scheduled out of order — you might schedule one for June, then one for May. And a fixed array requires expensive shifting to maintain ordering on insertion.

### Solution

A doubly linked list ordered by `effectiveTime`. Each node in the list carries:

- The action's type, effective time, and ABI-encoded parameters
- Pointers to the previous and next nodes in the list
- A status: either SCHEDULED (pending, cancellable) or COMPLETE (in the past, immutable)
- A monotonic ID, assigned only after the action's effective time passes

The list maintains time ordering as an invariant. When a new action is scheduled, the insertion logic finds the correct position by effective time and splices the node in. Insertion in the past (effective time ≤ current block timestamp) reverts — you cannot retroactively create history.

**Automatic execution.** Actions do not require a separate execution call. When any contract interaction occurs that needs to know the current state (a balance query, a transfer, a scheduling call), the system checks whether any scheduled actions have passed their effective time. Those actions transition to COMPLETE and receive their monotonic ID at that point. This means the historical record is immutable and gap-free: every completed action has a sequential ID, and no future action has one yet.

**Cancellation.** A scheduled action (one whose effective time has not yet passed) can be cancelled. Cancellation removes the node from the linked list entirely. Once an action's effective time passes and it becomes COMPLETE, it cannot be altered.

**Why a doubly linked list.** Singly linked lists only allow forward traversal. The most common read pattern is "what happened most recently?" or "are there any pending actions?" — both start from the tail. Backward traversal from the tail is essential for gas-efficient reads, since the assumption is that pending actions are rare (zero or one most of the time) and recent history is more relevant than ancient history.

### State Transitions

```
[does not exist] → SCHEDULED    (scheduling a new action)
SCHEDULED        → COMPLETE     (effective time passes, automatic)
SCHEDULED        → [removed]    (cancelled, node removed from list)
COMPLETE         → (terminal)   (immutable historical record)
```

There is no IN_PROGRESS state. Actions take effect atomically — they are either pending or complete. The IN_PROGRESS concept from the previous design was needed because execution was manual and could span multiple steps. With automatic execution, the transition from SCHEDULED to COMPLETE is atomic within a single transaction.

## Component 3: Action Types and Filtering

### Problem

Different corporate actions have different parameters, validation requirements, and downstream effects. A stock split has a ratio. A name change has a string. A dividend might have an amount and a record date. The data structure from Component 2 stores actions generically — it needs a type system to interpret them.

External consumers also need to query subsets of actions efficiently. An oracle only cares about balance-affecting actions. A UI might want all actions of any type. Iterating through the entire list and checking types one by one is wasteful if the type representation doesn't support efficient filtering.

### Solution

**Bitmap action types.** Each action type is represented as a single bit in a uint256 bitmap rather than a hash or sequential integer. The first type is `1 << 0`, the second is `1 << 1`, the third is `1 << 2`, and so on. This caps the maximum number of distinct action types at 256, which is more than sufficient.

The bitmap representation enables efficient filtering during list traversal. A caller constructs a mask by OR-ing together the types they care about, then each node can be checked with a single bitwise AND: `actionType & mask != 0`. No if/else chains, no mapping lookups during iteration.

A helper function converts human-readable type identifiers into their bitmap values, so external consumers don't need to know the bit positions.

**Stock splits** are the first concrete action type. A stock split's parameters encode a Rain float multiplier — the ratio by which all balances will be adjusted. The multiplier is validated at scheduling time: it must be expressible as a Rain float without precision loss.

**Filtering reads.** When traversing the list (Component 5), callers provide a bitmap mask. The traversal skips any node whose type doesn't match the mask. This means a single global list serves all use cases — there is no need for separate per-type lists, which would complicate insertion and increase storage costs.

## Component 4: Rebase Implementation

### Problem

This is the hard part. When a stock split's effective time passes, every holder's balance must change by the multiplier. But iterating over all holders is impossible, and virtual balance approaches (storing a global multiplier and computing balances on read) break down when users need to transfer specific amounts.

Consider: a user holds 100 base shares with pending multipliers that yield 30 effective shares. They want to transfer 1 share. With virtual balances, the system would need to convert "1 current share" back to base terms (dividing by the cumulative multiplier), introducing another rounding step on every single transfer. And the cumulative multiplier itself is wrong — sequential application of 1/3 × 3 × 1/3 × 3 gives a different result than collapsing to 1×.

The transfer problem makes virtual balances unworkable. The system needs to materialize effective balances, but only when accounts actually interact.

### Solution

**Lazy migration via `_update`.** Every account tracks a version representing which balance-affecting actions have been applied to its stored balance. A global counter increments each time a balance-affecting action (like a stock split) takes effect. When an account interacts via transfer, mint, or burn, the `_update` hook compares the account's version to the global version. If they differ, the account is migrated.

The migration sequence:

1. Read the account's stored balance and version
2. Apply each multiplier from (account version + 1) through (global version) sequentially using Rain float math
3. Write the resulting effective balance directly to storage
4. Update the account's version to the global version
5. Now apply the actual operation (the transfer/mint/burn amount)

Both sender and recipient must be migrated before a transfer executes. If only the sender is migrated, the transferred amount would be interpreted against incompatible balance states.

**Direct storage writes.** Migration writes the new balance directly to the ERC20 storage slot using assembly, rather than minting or burning the delta. Minting is semantically wrong for a redenomination — a stock split does not create new economic value, it changes the unit of account. Direct writes also avoid side effects: no spurious Transfer events, no totalSupply interference, no reentrancy concerns from recursive `_update` calls.

This couples the implementation to OpenZeppelin v5's ERC20Upgradeable storage layout (ERC-7201 namespaced at a known slot). The layout is stable for upgradeable contracts, and the coupling is documented and tested.

**Total supply.** When a balance-affecting action takes effect, `totalSupply` is eagerly updated via direct storage write — multiply the current total by the action's multiplier and write the result. This makes `totalSupply()` immediately correct after a split without waiting for individual account migrations.

Because individual account rounding (toward zero in Solidity) accumulates independently, the sum of all individually-migrated balances will be slightly less than the eagerly-computed totalSupply. This means totalSupply is a slight overestimate. The magnitude of the overestimate is bounded by the number of token holders (one wei of rounding per holder per rebase in the worst case). With 18-decimal tokens and the expectation that most tokens will be held in a wrapper contract (few holders of the unwrapped token), this error is negligible dust.

### Precision

Rain float math handles all multiplier calculations. This preserves exact fractional representation — a 1/3 multiplier stays as 1/3 through storage rather than becoming 0.333... in fixed-point.

The sequential application rule means precision loss accumulates predictably. After applying 1/3 × 3 × 1/3 × 3 to 100 shares, the result is 99.999... not 100. This is correct behaviour. The alternative — collapsing multipliers — would give different results depending on *when* an account migrates versus *which* actions it migrates through, breaking the invariant that all accounts converge to the same state.

Edge cases that need explicit handling: zero balances (should remain zero regardless of multipliers), balances near the precision floor of the float library, and balances near the maximum that could overflow during multiplication.

### `balanceOf` Override

`balanceOf()` is overridden to return the effective balance — the stored balance with all pending multipliers applied — without modifying state. This means external reads always see the correct current balance, even for accounts that haven't transacted since the last corporate action.

The override reads the stored balance directly from the ERC20 storage slot (same assembly access used for migration writes) and applies the multiplier chain. This is a view function with no state changes.

## Component 5: Downstream Query Interface

### Problem

External contracts — oracles, lending protocols, DEX integrations — need to make decisions based on corporate action state. An oracle needs to know if a split just happened so it can adjust its price feed. A lending protocol needs to know if a rebase is pending so it can pause liquidations during the transition period.

These contracts call into the vault during their own transaction execution, so query functions must be gas-efficient for onchain use, not just offchain reads.

### Solution

The query interface exposes corporate action state through the vault address (via the `ICorporateActionsV1` interface). Key queries:

**List traversal.** Callers can traverse the linked list from the tail backwards. Since pending actions are rare and recent history is most relevant, starting from the tail is the efficient default. Traversal accepts a bitmap mask to filter by action type.

**Action lookup by ID.** Completed actions have monotonic IDs. Given an ID, return the action's full metadata. An oracle can track the last ID it processed and catch up on any new ones.

**Pending actions.** Return actions whose effective time has not yet passed. These are at the tail of the list (after all completed actions). External systems can use this to anticipate upcoming corporate actions and plan accordingly.

**Effective balance.** Given an account address, return what the balance would be after applying all pending migrations. This is a view function — it does not modify state — but it gives external contracts accurate balance information without requiring the account to transact first.

**Global version.** The current version number for balance-affecting actions, enabling external contracts to detect whether any new rebases have occurred since they last checked.

The interface must return consistent results. Because actions take effect automatically (no manual execution step), any read that triggers the detection of a newly-past effective time will see that action as COMPLETE with its assigned ID. State updates and event emissions are ordered so that queries within the same block see a consistent snapshot.

## Receipt Coordination

Receipt tokens (ERC-1155) represent the same underlying positions as vault shares (ERC-20). When a corporate action adjusts vault share balances, receipt balances must adjust proportionally. If they diverge, holders could arbitrage between the two representations.

The vault already has a manager relationship with the receipt contract — `receipt().managerMint()` and `receipt().managerBurn()` are used during deposits and withdrawals. Corporate actions use this same mechanism. When a rebase takes effect, the vault calls through the manager interface to apply matching adjustments to receipt balances.

The receipt system needs its own version tracking, mirroring the vault's approach. When a receipt is transferred or redeemed, its balance is migrated using the same sequential multipliers. The shared multiplier data lives in `LibCorporateAction` storage, accessible to both the vault's ERC-20 logic and the receipt contract's manager-called functions.

Atomicity is essential. If the vault rebase succeeds but the receipt update fails, the transaction must revert entirely. Partial application would create an inconsistent state that cannot be corrected after the fact.
