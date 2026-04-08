# Pass 1 — Security Review

Scope: the full `src/` tree. Files modified in the corporate-actions stack (#18 → #22 → #23 → #21 → #24 → #25) re-reviewed in full; unchanged files carried forward by reference from `audit/2026-04-07-01/pass1/`.

## Files reviewed in full (this run)

Each file was read line-by-line with prior audit context loaded for cross-reference.

1. `src/concrete/StoxCorporateActionsFacet.sol` (132 lines)
2. `src/concrete/StoxReceiptVault.sol` (82 lines)
3. `src/interface/ICorporateActionsV1.sol` (95 lines)
4. `src/lib/LibCorporateAction.sol` (223 lines)
5. `src/lib/LibCorporateActionNode.sol` (110 lines)
6. `src/lib/LibERC20Storage.sol` (59 lines)
7. `src/lib/LibRebase.sol` (88 lines)
8. `src/lib/LibStockSplit.sol` (35 lines)
9. `src/lib/LibTotalSupply.sol` (171 lines)

## Status of prior-run findings (2026-04-07-01)

Verified at current stack tip (`4c2b7eb`):

- **A03-1 / A26-1 (CRITICAL)** — fresh-recipient inflation: **FIXED** on PR4 (`cd32c88 fix(rebase): advance cursor for zero-balance accounts`). LibRebase now walks completed splits in the zero-balance branch and returns the advanced cursor. Verified lines 52–59.
- **A28-1 (HIGH)** — pots / balanceOf divergence: **FIXED** as a consequence of A03-1 plus `62d10f6 fix(audit): ... integration tests for totalSupply`. Per-account migration + pot math now reconciles.
- **A23-1 (MEDIUM)** — OZ storage drift detection: **FIXED** on PR4 (`57ecc0d test(audit): LibERC20Storage runtime invariant test against OZ ERC20Upgradeable`).
- **A01-P5-1 (MEDIUM)** — CompletionFilter parameter on the four traversal getters: **FIXED** on PR6 (`4c2b7eb`). Interface and facet now take `CompletionFilter`.
- **A01-1 (LOW)** — per-action context to authorizer: **FIXED** on PR1 (`66e917a fix(audit): forward per-action context to authorizer + facet auth tests`). Facet `_authorize` now passes `abi.encode(typeHash, effectiveTime, parameters)` for schedule and `abi.encode(actionIndex)` for cancel.
- **A21-1 (LOW)** — unbounded `parameters` bytes: **DISMISSED** in prior triage (authorizer is the safeguard). Current run respects that disposition.
- **A26-P2-2 / related (LOW)** — second-action-type tests: deferred in prior triage ("speculative until a second action type exists"). Still speculative. No re-flag.

## New findings (this run)

### P1-1 — `LibStockSplit.validateParameters` still permits near-zero and near-saturation multipliers (previously A27-1, deferred)

**Severity:** MEDIUM

**Location:** `src/lib/LibStockSplit.sol:16-20`

The prior run raised this as A27-1 and prior triage deferred it with "bound choice still open". The implementation is unchanged: `validateParameters` only rejects `coefficient <= 0` on the Float representation. That leaves two attack surfaces open:

1. **Near-zero multipliers.** A multiplier with positive coefficient but very negative exponent (e.g. `Float(1, -30)`) truncates every realistic per-account balance to 0 on the first `toFixedDecimalLossy` in `LibRebase.migratedBalance` and `LibTotalSupply.effectiveTotalSupply`. The entire vault's balances are wiped in a single `scheduleCorporateAction` call, and the wipe becomes irreversible once `effectiveTime` passes (cancel is rejected for complete actions, per `LibCorporateAction.cancel` line 161).
2. **Near-saturation multipliers.** A large positive coefficient / positive exponent pair can take a realistic uint256 balance through a sequential rebase into a Float that, on the next `toFixedDecimalLossy`, either reverts from overflow inside `rain.math.float` or returns a wrapped value. Either way, the vault becomes unusable until the authorizer schedules a compensating reverse split — which may itself be blocked by the same ceiling.

**Why this is still MEDIUM in 2026-04-08-01:**
- The per-action context is now forwarded to the authorizer (A01-1 fix), so an authorizer policy *could* gate on multiplier magnitude externally. But the contract itself offers no floor or ceiling, so the safety of the system still reduces entirely to authorizer policy. That is a durable delegation of invariant-preservation to an external component, and the authorizer is itself an upgradable address — an upgrade bug in the authorizer fully exposes the contract.
- PR stack is targeting merge; the "bound choice still open" deferral in 2026-04-07-01 has no committed owner and no timeline. Re-raising to force a decision this run.

**Reproduction (near-zero):** `schedule(STOCK_SPLIT_TYPE_HASH, t+1, abi.encode(LibDecimalFloat.packLossless(1, -30)))`. Validation passes (coefficient == 1 > 0). At `t+1`, `balanceOf(anyone)` returns 0.

**PR attribution:** **PR3 (#23, `feat/corporate-actions-pr3-action-types`)** — this is where `LibStockSplit.validateParameters` and its tests were introduced (`d399f73 feat: stock split type with consistent encode/decodeParameters naming`). Fix lands on PR3 and cascades up the stack via restack.

**Proposed fix:** see `.fixes/P1-1.md`. Implements:
- Floor: reject any multiplier whose `toFixedDecimalLossy(_, 0)` applied to `1e18` (a reasonable minimum "meaningful" stake denomination) rounds to zero. Equivalently: require `mul(packLossless(1e18, 0), multiplier) >=_fixed 1`.
- Ceiling: reject any multiplier whose application to `type(uint128).max` would exceed `type(uint256).max` after rasterization. This keeps a comfortable gap between realistic supply (~`2**96` for most RWA) and the overflow wall.
- Keep the existing `coefficient <= 0` check (it's necessary for the sign rejection; the float floor does not subsume it for negative coefficients with positive exponents that still produce a representable positive on unpack).
- New errors: `MultiplierTooSmall(Float)`, `MultiplierTooLarge(Float)`, both reverting with the offending Float for post-mortem clarity.

### P1-2 — `schedule()` linked-list walk is O(n) in scheduled-but-not-completed actions

**Severity:** INFO

**Location:** `src/lib/LibCorporateAction.sol:127-143`

`schedule()` walks backward from `s.tail` to find the correct insertion point, so scheduling the Nth pending action costs O(N) reads. This is a classic DoS vector for authorizer-gated state growth, but:
- Pending-action count is bounded in practice (issuers schedule a handful per year).
- Writes are permissioned by the authorizer.
- Cancelled / completed nodes are *not* removed from the array but *are* unlinked from the list, so the walk terminates early once it hits a completed-or-cancelled node via the `effectiveTime <= current` branch.

INFO-only: flagged so that if an action type ever lands whose scheduling cadence is adversarial (e.g. on-chain-triggered schedules rather than manual ones), this gets revisited. Not worth fixing today.

**PR attribution:** PR2 (#22).

## Items deliberately not flagged

- Out-of-bounds cursor inputs to `LibCorporateActionNode.nextOfType/prevOfType` causing Solidity panic (0x32) on `s.nodes[fromIndex].next/prev`. Prior run dismissed as "defensible default behavior" (`audit/2026-04-07-01/pass1/LibCorporateActionNode.md`, items deliberately not flagged). I agree for library-internal callers, and for external callers the facet getters propagate the panic verbatim — nondistinctive but not unsafe. Re-raising would be litigating a prior decision without new information.
- Reentrancy via authorizer callback in `scheduleCorporateAction` / `cancelCorporateAction` — prior A01-2 INFO, still INFO. Authorizer is trusted; state writes happen after the external call but no prior state is read-modify-written around it.
- `int256(balance)` / `int256(running)` unguarded casts in LibRebase and LibTotalSupply — prior A26-2 INFO. Realistic supply is well below `2**255`; the `forge-lint` suppression is explicit.
- `LibERC20Storage.setTotalSupply` is live-but-unused. Dead code is a Pass 4 concern, not a Pass 1 issue. Will be flagged in Pass 4 if still unused there.
- `effectiveTotalSupply` walks all completed splits on every call (O(completed splits)). Real-world completed-split count is small; not a DoS vector.
- `schedule`/`resolveActionType` order (external call → validation → state write): no CEI inversion risk because the authorizer is the only external touchpoint and state is not read-modify-written around it.

## Files carried forward by reference (unchanged since 2026-04-07-01)

`src/diff main...HEAD` confirms the non-stack files are untouched since the prior audit. Carried forward:

- `src/concrete/StoxReceipt.sol`
- `src/concrete/StoxWrappedTokenVault.sol`
- `src/concrete/StoxWrappedTokenVaultBeacon.sol`
- `src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol`
- `src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol`
- `src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol`
- `src/concrete/deploy/StoxUnifiedDeployer.sol`
- `src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol`
- `src/generated/*.pointers.sol` (auto-generated)
- `src/lib/LibProdDeployV1.sol`
- `src/lib/LibProdDeployV2.sol`

No Pass 1 findings from `audit/2026-03-19-01/pass1/` for those files remain open.
