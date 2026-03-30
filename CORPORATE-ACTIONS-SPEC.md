# Corporate Actions via Diamond Facet

## Overview

This specification defines a comprehensive corporate actions system implemented as a diamond facet, addressing the fundamental challenge of applying balance changes to thousands of token holders while maintaining precision, predictable gas costs, and operational reliability for downstream consumers.

## Critical Implementation Requirements

### Diamond Facet Integration

The diamond facet approach is essential because corporate actions require complex functionality that would exceed contract size limits if implemented directly in the vault. The critical requirement is maintaining the existing vault address for external contract compatibility while enabling extensible functionality. The shared storage pattern via LibCorporateAction must use collision-resistant storage slots and provide atomic state transitions that cannot be corrupted by partial execution.

The facet integration must preserve all existing vault functionality without regression. Authorization patterns must remain consistent with the existing RBAC system, and the storage layout must be designed for future extensibility without requiring storage migrations.

### Execution Timing and Operational Certainty

The 4-hour execution window is not arbitrary but addresses a critical operational requirement: downstream consumers need predictable timing to make automated decisions. Without enforced deadlines, corporate actions could remain unexecuted indefinitely, creating uncertainty for oracles, lending protocols, and automated strategies that depend on reliable timing.

The execution window must be enforced at the contract level, not just operationally. Actions that are not executed within the window must automatically expire and become unexecutable. This provides hard guarantees to external systems about when corporate action effects will occur, enabling them to schedule pause windows, recalibrate pricing models, or adjust risk parameters with confidence.

The timing enforcement must handle edge cases correctly: actions scheduled with effective times in the past, concurrent execution attempts, and system clock dependencies. The state transition from SCHEDULED to EXPIRED must be irreversible to prevent confusion about action status.

### Version-Based Lazy Migration System

The lazy migration system solves three interconnected problems that simpler approaches cannot handle: unbounded gas costs, precision preservation, and operational necessity for balance transfers.

The version tracking system must maintain perfect consistency between account states and global state. Each account's version number represents exactly which corporate actions have been applied to their balance. When accounts interact, the migration process must apply all missed corporate actions in exact sequential order, updating the account to the current global version atomically.

The critical implementation detail is that migration must happen for both sender and recipient before any balance transfer occurs. This ensures both parties operate on current effective balances, preventing scenarios where one party is at version 5 and another at version 8 attempting to transfer between incompatible balance states.

The sequential multiplier application preserves computational precision characteristics that would be lost with cumulative multiplication. Consider multipliers 1/3, 3, 1/3, 3 applied sequentially versus the cumulative equivalent of 1.0. Sequential application yields 99.999999 due to accumulated rounding, while cumulative yields exactly 100.0. The system must preserve the sequential result for computational consistency - all accounts migrated later must get identical results to accounts that transferred after each corporate action.

The operational necessity emerges from the impossibility of meaningful balance arithmetic with virtual multipliers. When a user wants to transfer "1" current share from an account with 100 base shares and pending multipliers yielding 30 effective shares, the system cannot perform this operation without first materializing the effective balance. Division approaches (transferring 3.33 base shares) introduce additional precision errors and computational complexity on every transfer.

### Storage Architecture for Query Reliability

The storage design must support both efficient internal operations and reliable external queries. Corporate actions must be stored with sequential identifiers that enable external contracts to iterate through all actions deterministically. The storage pattern must handle concurrent reads during execution without returning inconsistent states.

Each corporate action must store sufficient metadata for external contracts to understand timing, effects, and status without requiring additional lookups. Action type identifiers must be standardized and comprehensive enough for external systems to make informed decisions about their operational impact.

The event emission strategy is critical for offchain indexing and external system integration. Events must provide complete information about corporate action lifecycle changes, enabling external systems to maintain their own cached views of corporate action state without constant onchain queries.

### Authorization and Security Model

The authorization system must prevent several attack vectors while maintaining operational efficiency. Different corporate action types may require different authorization levels - routine stock splits might be executable by operators, while extraordinary actions require governance approval.

The execution permission model must be separate from scheduling permissions to enable operational flexibility. Hot wallets may need to execute scheduled actions without having the authority to schedule new actions. The permission structure must prevent unauthorized modification of scheduled actions while allowing legitimate operational execution.

The timing enforcement provides additional security by creating predictable windows for action execution, preventing actions from being executed at unexpected times that could manipulate market conditions or user expectations.

### Precision Requirements and Computational Correctness

The precision requirements stem from the need for deterministic, reproducible calculations across different execution contexts. The Rain float math integration must handle fractional split ratios exactly, supporting ratios like 3:2 and 5:4 without accumulating errors that would diverge from intended outcomes over multiple corporate actions.

Split ratio validation must prevent problematic inputs that could cause precision issues or system instability. Complex decimal ratios like 2.73:1 are prohibited not for simplicity but because they introduce precision errors that accumulate unpredictably through sequential application.

The system must handle edge cases in precision correctly: zero balances after migration, very small balances that approach the precision limits of the float library, and maximum balance limits that could cause overflow during multiplication.

### Receipt System Coordination

The vault-receipt coordination leverages the existing manager relationship to maintain consistency without introducing parallel version systems. When corporate actions execute in the vault, they must trigger proportional updates in the receipt system using the same multipliers and precision calculations.

The critical requirement is atomic coordination - if a corporate action succeeds in the vault but fails in the receipt update, the entire transaction must revert to prevent inconsistent states between ERC20 and ERC1155 representations of the same underlying positions.

The manager relationship prevents the need for complex cross-contract communication patterns while ensuring that receipt holders experience identical corporate action effects to direct vault share holders. This maintains the equivalence between holding vault shares directly and holding receipts as proof of vault positions.

### External Contract Integration

External contracts must be able to depend on the query interface for operational decisions. This means query functions must return consistent, complete information even during corporate action execution. Race conditions where external contracts see partial or inconsistent corporate action states must be prevented through careful ordering of state updates and event emissions.

The query interface must be designed for gas efficiency when called by other contracts during transaction execution. External contracts may need to check corporate action status during their own operations, so query functions must be optimized for onchain execution, not just offchain analysis.

The single address requirement is critical for integration reliability. External contracts should not need to track multiple registry addresses or understand complex routing logic to access corporate action information. All necessary data must be accessible through the vault address they already depend on for balance information.