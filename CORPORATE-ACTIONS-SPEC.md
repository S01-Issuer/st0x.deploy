# Corporate Actions Specification

## Overview

A corporate action like a stock split must adjust the balance of every token holder simultaneously. Iterating over all holders in a single transaction is impossible at scale, so the system needs a mechanism that achieves the economic effect of a simultaneous adjustment without actually touching every account.

This specification describes five components that together solve this problem. Each component builds on the one before it: the diamond facet provides the architectural foundation, the framework provides scheduling and lifecycle management, supply-changing actions define the triggers, the rebase system implements the actual balance adjustments, and the query interface exposes state to external contracts.

## Design Principles

### Framework Principles

**Single source of truth.** All corporate action state lives on the vault itself. External contracts already depend on the vault address for balance queries — they should not need to discover or trust a separate registry.

**Operational certainty.** Downstream systems (oracles, lending protocols, automated strategies) need to know *when* effects will land. Enforced execution windows turn "this action might happen eventually" into "this action will either execute in this window or expire." External systems can schedule around that.

**Extensibility without migration.** The framework must support future corporate action types (dividends, name changes, mergers) without storage migrations or vault redeployment.

### Rebase Principles

**Sequential precision over mathematical equivalence.** Applying multipliers 1/3, 3, 1/3, 3 sequentially to 100 yields 99.999... due to accumulated rounding. Collapsing them into a single 1× multiplier yields exactly 100. The system must preserve the sequential result. This is not a bug — it is a deliberate choice that guarantees every account gets identical results regardless of when they interact with the contract. An account that transferred after every corporate action and an account that was dormant for a year must arrive at the same balance when they finally transact.

**Rasterize on write, never scale input.** When a user says "transfer 1 share," that means 1 share in current terms. The system must materialize (rasterize) the effective balance from stored base balance plus pending multipliers before applying any operation. Attempting to reverse-engineer a base amount from a current-terms input introduces additional precision errors and breaks user expectations.

**Migration is invisible.** Account holders should never need to call a separate "migrate" function. Migration happens automatically as a pre-step to any balance-changing operation (transfer, mint, burn) via the `_update` hook.

## Component 1: Diamond Facet Foundation

### Problem

Corporate actions require substantial logic — scheduling, state machines, multiplier storage, migration tracking, query interfaces. Adding this directly to the vault would exceed contract size limits. But the vault address must remain the single point of contact for external systems.

### Solution

A diamond facet delegates corporate action logic to a separate contract while preserving the vault's address as the entry point. The facet's storage lives in the vault's storage space using a collision-resistant slot (ERC-7201 namespaced storage), consistent with the vault's existing storage patterns.

The facet needs its own authorization integration. Scheduling a corporate action and executing one are distinct privileges — an operator hot wallet may execute scheduled actions without having authority to schedule new ones.

## Component 2: Corporate Action Framework

### Problem

Corporate actions have a lifecycle: they are announced in advance, have an effective time, must be executed within a reasonable window, and are either completed or expired. Without enforced lifecycle management, actions can linger indefinitely in ambiguous states, making it impossible for external systems to plan around them.

### Solution

The framework manages corporate actions through a state machine: SCHEDULED → IN_PROGRESS → COMPLETE, with EXPIRED as a terminal state reachable from SCHEDULED when the execution window closes.

Each action has an effective time and a fixed execution window (4 hours). The window is enforced at the contract level — attempting to execute after expiry reverts. This is not merely operational convention; it is an onchain guarantee that external systems can depend on.

Actions are stored with sequential identifiers so external contracts can iterate through the full history deterministically. Each action record carries enough metadata (type, timing, parameters, status) for external systems to understand its impact without additional lookups.

Events mark every lifecycle transition. External indexers can reconstruct the complete corporate action history from events alone without polling storage.

## Component 3: Supply-Changing Actions

### Problem

Different corporate actions have different parameters and validation requirements. A 2-for-1 stock split and a 1-for-3 reverse split are both ratio-based, but a dividend might be amount-based. The framework needs to accommodate different action types without special-casing each one in the core lifecycle logic.

### Solution

Each corporate action type is a distinct implementation that plugs into the framework's lifecycle. Stock splits are the first implementation and serve as the template for future types.

A stock split specifies a ratio (e.g., 3:2). The ratio must be expressible as a Rain float without precision loss — complex decimal ratios like 2.73:1 are rejected at scheduling time because they would accumulate unpredictable errors through sequential application. The action records its multiplier in the global action history when executed, making it available for the migration system.

The framework is deliberately agnostic about what happens when an action executes. Component 3 defines the *trigger and parameters*. Component 4 defines the *balance effects*.

## Component 4: Rebase Implementation

### Problem

This is the hard part. When a 2-for-1 split executes, every holder's balance must double. But iterating over all holders is impossible, and virtual balance approaches (storing a global multiplier and computing balances on read) break down when users need to transfer specific amounts.

Consider: a user holds 100 base shares with pending multipliers that yield 30 effective shares. They want to transfer 1 share. With virtual balances, the system would need to convert "1 current share" back to base terms (dividing by the cumulative multiplier), introducing another rounding step on every single transfer. And the cumulative multiplier itself is wrong — sequential application of 1/3 × 3 × 1/3 × 3 gives a different result than collapsing to 1×.

The transfer problem makes virtual balances unworkable. The system needs to materialize effective balances, but only when accounts actually interact.

### Solution

Every account tracks a version number representing which corporate actions have been applied to its stored balance. A global version increments each time a corporate action executes. When an account interacts (via transfer, mint, or burn), the `_update` hook compares the account's version to the global version. If they differ, the account is migrated: each missed multiplier is applied sequentially to the stored balance, and the version is updated.

The write operation sequence is precise:

1. Read the account's stored balance and version
2. Apply each multiplier from (account version + 1) through (global version) sequentially
3. Write the resulting effective balance as the new stored balance
4. Update the account's version to global version
5. Now apply the actual operation (the transfer/mint/burn amount)

Both sender and recipient must be migrated before a transfer executes. If only the sender is migrated, the transferred amount would be interpreted against incompatible balance states.

The `_update` hook in OpenZeppelin v5's ERC20 is the natural integration point — it is called for every transfer, mint, and burn, and it receives both `from` and `to` addresses.

### Precision

Rain float math handles all multiplier calculations. This preserves exact fractional representation — a 1/3 multiplier stays as 1/3 through storage rather than becoming 0.333... in fixed-point.

The sequential application rule means precision loss accumulates predictably. After applying 1/3 × 3 × 1/3 × 3 to 100 shares, the result is 99.999... not 100. This is correct behaviour. The alternative — collapsing multipliers — would give different results depending on *when* an account migrates versus *which* actions it migrates through, breaking the invariant that all accounts converge to the same state.

Edge cases that need explicit handling: zero balances (should remain zero regardless of multipliers), balances near the precision floor of the float library, and balances near the maximum that could overflow during multiplication.

## Component 5: Downstream Query Interface

### Problem

External contracts — oracles, lending protocols, DEX integrations — need to make decisions based on corporate action state. An oracle needs to know if a split just happened so it can adjust its price feed. A lending protocol needs to know if a rebase is pending so it can pause liquidations during the execution window.

These contracts call into the vault during their own transaction execution, so query functions must be gas-efficient for onchain use, not just offchain reads.

### Solution

The query interface exposes corporate action state through the vault address. Key queries:

**Action history**: retrieve actions by sequential ID, enabling deterministic iteration. An oracle can track the last action ID it processed and catch up on any new ones.

**Current state**: whether an action is scheduled, in progress, or complete. External contracts can check this during their own operations to decide whether to proceed or pause.

**Effective balance**: given an account address, return what the balance would be after applying all pending migrations. This is a view function — it does not modify state — but it gives external contracts accurate balance information without requiring the account to transact first.

**Global version**: the current version number, enabling external contracts to detect whether any new corporate actions have occurred since they last checked.

The interface must return consistent results even during corporate action execution. State updates and event emissions must be ordered so that queries within the same block see either the pre-action or post-action state, never a partial intermediate.

## Receipt Coordination

Receipt tokens (ERC-1155) represent the same underlying positions as vault shares (ERC-20). When a corporate action adjusts vault share balances, receipt balances must adjust proportionally. If they diverge, holders could arbitrage between the two representations.

The vault already has a manager relationship with the receipt contract — `receipt().managerMint()` and `receipt().managerBurn()` are used during deposits and withdrawals. Corporate actions use this same mechanism. When a rebase executes, the vault calls through the manager interface to apply matching adjustments to receipt balances.

The receipt system needs its own version tracking, mirroring the vault's approach. When a receipt is transferred or redeemed, its balance is migrated using the same sequential multipliers. The shared multiplier data lives in `LibCorporateAction` storage, accessible to both the vault's ERC-20 logic and the receipt contract's manager-called functions.

Atomicity is essential. If the vault rebase succeeds but the receipt update fails, the transaction must revert entirely. Partial application would create an inconsistent state that cannot be corrected after the fact.
