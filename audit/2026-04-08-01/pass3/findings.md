# Pass 3 — Documentation Review

Scope: stack-modified source files re-reviewed for NatSpec completeness and accuracy; unchanged files carried forward by reference.

## Files reviewed

1. `src/concrete/StoxCorporateActionsFacet.sol`
2. `src/concrete/StoxReceiptVault.sol`
3. `src/interface/ICorporateActionsV1.sol`
4. `src/lib/LibCorporateAction.sol`
5. `src/lib/LibCorporateActionNode.sol`
6. `src/lib/LibERC20Storage.sol`
7. `src/lib/LibRebase.sol`
8. `src/lib/LibStockSplit.sol`
9. `src/lib/LibTotalSupply.sol`

## Status of prior-run findings (2026-04-07-01)

- **A20-P3-1 (LOW)** — interface silent on completion semantics: **FIXED** on PR6 (`4c2b7eb`). The four traversal getters now take an explicit `CompletionFilter` parameter with NatSpec describing `ALL` / `COMPLETED` / `PENDING` and the oracle guidance.
- **A21-P3-1 (LOW)** — `head()` / `tail()` NatSpec: **FIXED** on PR2 (`4447bcb fix(audit): forge fmt + head/tail NatSpec on LibCorporateAction`). Lines 212–222 now have complete `@notice` + `@return`.
- **A01-P3-1 (LOW)** — event NatSpec: **FIXED** on PR1 (`8ab783a fix(audit): CLAUDE.md updates + facet event/contract NatSpec`). Both `CorporateActionScheduled` and `CorporateActionCancelled` now have per-field `@param` documentation.
- **A01-P3-2 (LOW)** — contract `@dev` on delegatecall requirement: **FIXED** on PR1 (same commit). Contract NatSpec now explicitly states the facet "MUST be delegatecalled by an `OffchainAssetReceiptVault`-derived contract."
- **A01-P3-3 (INFO)** — `_authorize` `@param` tags: **FIXED** on PR1. All three parameters documented.
- **A21-P3-2 (INFO)** — storage struct cross-file relationship: INFO only; no change made, still open as INFO. Not worth re-raising.

## Outstanding from prior run

- **A03-P3-1 (LOW)** — `AccountMigrated` event lacks per-field `@param` tags. **NOT FIXED** in the current `StoxReceiptVault.sol:25-27`. See P3-1 below.
- **A03-P3-2 (INFO)** — `balanceOf` / `totalSupply` override lack `@return` tags. Still INFO; re-flagged as P3-2.
- **A27-P3-1 (LOW)** — `LibStockSplit.validateParameters` NatSpec says "positive non-zero Rain float" but the check is coefficient-only. Depends on P1-1's bound landing; the doc update ships with that fix. See P3-3.
- **A20-P3-2 (INFO)** — interface does not expose action type bitmap constants. Still open. See P3-4.
- **A03-P3-3 (INFO)** — "migration" is overloaded between balance rasterization and cursor advancement. Still open; the current contract NatSpec reads the same as the prior-run snapshot. Re-raised in P3-5 because the A03-1 bug-post-mortem now lives in the library NatSpec (`LibRebase.sol:28-33`) and the contract NatSpec's "lazy migration" phrasing should cross-reference it.

## New findings (this run)

### P3-1 — `AccountMigrated` event lacks per-field `@param` documentation

**Severity:** LOW

**Location:** `src/concrete/StoxReceiptVault.sol:24-27`

```solidity
/// Emitted when an account is migrated through pending stock splits.
event AccountMigrated(
    address indexed account, uint256 fromCursor, uint256 toCursor, uint256 oldBalance, uint256 newBalance
);
```

A single summary line covers five fields. Indexers consuming the event cannot tell from the source whether `oldBalance` is the *stored* balance before rasterization or the *effective* balance before rasterization — these are different under a completed split. Similarly `fromCursor`/`toCursor` semantics aren't pinned.

**PR attribution:** **PR4 (#21)**, `feat/corporate-actions-pr4-rebase`, commit `e6d8b82` (where the event was first introduced).

**Proposed fix:** `.fixes/P3-1.md` — adds `@notice` + five `@param` tags.

### P3-2 — `balanceOf` / `totalSupply` overrides lack `@return` documentation

**Severity:** INFO

**Location:** `src/concrete/StoxReceiptVault.sol:30, 38`

```solidity
/// @dev Returns the balance including any pending rebase multipliers.
function balanceOf(address account) public view virtual override returns (uint256) { ... }

/// @dev Returns the effective total supply including pending multipliers.
function totalSupply() public view virtual override returns (uint256) { ... }
```

Both functions use `@dev` only. A `@return` tag clarifying the post-rebase semantics (and, for balanceOf, that it does NOT trigger state mutation even if the stored balance is stale) would help. INFO because the overrides inherit the parent ERC20 `@notice`.

**PR attribution:** **PR4 (#21)**.

**Proposed fix:** `.fixes/P3-2.md`.

### P3-3 — `LibStockSplit.validateParameters` NatSpec claim "positive non-zero Rain float" understates the validation

**Severity:** LOW (paired with P1-1)

**Location:** `src/lib/LibStockSplit.sol:13-16`

```solidity
/// @notice Validate that encoded parameters contain a valid stock split
/// multiplier. The multiplier must be a positive non-zero Rain float.
/// @param parameters ABI-encoded Float.
```

"Positive non-zero" suggests mathematical positivity. A Float with `coefficient=1` and `exponent=-30` is mathematically positive but functionally zero for any realistic balance — the validation does not reject it (see P1-1). Doc and implementation disagree on what "positive" means. After P1-1 lands the bound, this NatSpec must update to describe the actual floor and ceiling.

**PR attribution:** **PR3 (#23)** — co-located with P1-1.

**Proposed fix:** bundled with `.fixes/P1-1.md` (doc update lands with the bound fix).

### P3-4 — `ICorporateActionsV1` does not expose action type constants

**Severity:** INFO

**Location:** `src/interface/ICorporateActionsV1.sol` (no constants defined)

The interface returns an opaque `uint256 actionType` in the four traversal getters. External consumers (oracles, wrappers, UIs) have to know that `1 << 0` means stock split, and for any future action types the mapping is only documented in `LibCorporateAction.sol` — which is not a public interface surface. Oracle integrators importing just `ICorporateActionsV1.sol` cannot read the type mapping.

Two acceptable dispositions:
1. Define `uint256 constant ACTION_TYPE_STOCK_SPLIT = 1 << 0;` at file scope in the interface file (Solidity 0.8.x supports file-level constants alongside interfaces). New consumers import them from `ICorporateActionsV1.sol`.
2. Add a `@dev` block in the interface NatSpec listing the canonical mapping and pointing at `LibCorporateAction` as the authoritative source.

Option 1 is cleaner but requires the lib to also re-import from the interface to avoid duplication. Option 2 is zero-code.

**PR attribution:** **PR1 (#18)** (where `ICorporateActionsV1` is defined) or **PR6 (#25)** (where the traversal getters using the `actionType` return value were introduced). Lands on **PR6** because the constant's visibility is only user-facing once the getters that return the `actionType` exist.

**Proposed fix:** `.fixes/P3-4.md` — Option 2 (zero-code NatSpec `@dev` block).

### P3-5 — `StoxReceiptVault` contract NatSpec should cross-reference the A03-1 post-mortem in `LibRebase`

**Severity:** INFO

**Location:** `src/concrete/StoxReceiptVault.sol:11-22`

The contract NatSpec describes the lazy migration model but uses "migration" for two conceptually distinct operations: rasterizing the stored balance, and advancing the per-account cursor. The A03-1 bug existed because these came apart for zero-balance accounts. The library-level NatSpec in `LibRebase.sol:28-33` now explains this distinction in full, but the vault-level NatSpec doesn't reference it. A reader entering through the vault won't discover why cursor advancement is load-bearing for fresh recipients.

**PR attribution:** **PR4 (#21)**.

**Proposed fix:** `.fixes/P3-5.md` — one-line cross-reference.

## Items deliberately not flagged

- `LibTotalSupply.sol` top-of-file library NatSpec is exemplary — pot model, migration formula, convergence, fold semantics all described. No finding.
- `LibCorporateActionNode.sol` — library, struct, enum, and both functions all have complete NatSpec including the filter early-break rationale. No finding.
- `LibERC20Storage.sol` — `SAFETY:` block on the OZ layout dependency is explicit and referenced by CLAUDE.md line 55. No finding.
- `LibRebase.sol` — `migratedBalance` NatSpec explicitly calls out the cursor-advancement-for-zero-balance rationale and cross-references the 2026-04-07-01 audit artifacts. No finding.
- `StoxCorporateActionsFacet.sol` — contract, events, all external functions and the internal `_authorize` now have complete NatSpec. No new finding.
- `LibCorporateAction.sol` internal functions (`schedule`, `cancel`, `countCompleted`) — use `@notice` but not `@param`. Internal library; prior-run audit accepted this level. Not relitigated.

## Files carried forward by reference

Non-stack source files have unchanged NatSpec and no open Pass 3 findings from `audit/2026-03-19-01/pass3/`.
