<!-- SPDX-License-Identifier: LicenseRef-DCL-1.0 -->
<!-- SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd -->

# Corporate Action Registry — Implementation Plan

## Status: In Progress

## Overview

Add a corporate action registry to st0x.deploy that enables onchain scheduling
and execution of corporate actions against StoxReceiptVault tokens. The registry
exposes onchain readable state so downstream protocols can query and react to
upcoming and in-progress corporate actions.

---

## Milestone 1: Registry + Name/Symbol Changes

### PR 1: CorporateActionRegistry contract
- [x] `src/concrete/CorporateActionRegistry.sol`
  - Token-agnostic, standalone contract
  - `schedule(token, actionType, data, effectiveTime)` — schedule future action
  - `execute(token, actionType, number)` — execute after effective time, within execution window
  - Action lifecycle: SCHEDULED → IN_PROGRESS → COMPLETE
  - Namespaced per-token, per-action-type sequential IDs (counters)
  - Global execution window (4 hours) — actions expire if not executed within window
  - Read interface: `getAction()`, `getCounter()`, `getActionState()`
  - Events: `CorporateActionScheduled`, `CorporateActionExecuted`
  - Authorisation via token's authoriser (registry must hold the relevant role)
- [x] Error types in `src/error/ErrCorporateActionRegistry.sol`
- [x] Tests: registry lifecycle (schedule, time travel, execute, reverts, expiry)

### PR 2: StoxAuthorizer (extends OffchainAssetReceiptVaultAuthorizerV1)
- [x] `src/concrete/authorize/StoxAuthorizer.sol`
  - Extends `OffchainAssetReceiptVaultAuthorizerV1` from ethgild
  - Adds `UPDATE_NAME_SYMBOL` permission + `UPDATE_NAME_SYMBOL_ADMIN` role
  - Future: `REBASE` permission (not this milestone)
  - Same RBAC pattern as existing permissions
  - `initialAdmin` gets all new admin roles on init
- [x] Tests: role grants, authorize calls, unauthorised reverts, delegation, fuzz

### PR 3: StoxReceiptVault name/symbol override
- [x] Modify `src/concrete/StoxReceiptVault.sol`
  - ERC-7201 namespaced storage for name/symbol overrides
  - `name()` / `symbol()` overrides (fall through to super if not set)
  - `updateNameSymbol(actionType, number, newName, newSymbol)` — gated by authoriser
- [x] Tests: name/symbol fallthrough, authorised update, event emission,
  multiple updates, unauthorised revert, revocation revert, empty input
  reverts, fuzz
- [x] e2e tests in CorporateActionRegistry.t.sol: full flow through registry

### Design Decision: CAID deferred to Milestone 2
CAID (Corporate Action ID) tracking is intentionally NOT included in name/symbol
changes. Name/symbol updates are cosmetic — they don't affect balances or
pricing. CAID-aware transfers (`transferCA`) would false-revert on harmless
ticker changes. CAID will be added with economically meaningful actions
(rebasing/splits) where stale-state protection matters.

---

## Future Milestones (not yet scoped)

### Milestone 2: Rebasing / Stock Splits
- Rebase multiplier storage + lazy migration in StoxReceiptVault
- `_update()` hook with rasterize-then-update pattern
- `applyRebase()` gated by authoriser
- ERC-1155 receipt rebasing in StoxReceipt
- `REBASE` permission in StoxAuthorizer
- CAID storage + `currentCAID()` getter + `_computeCAID()`
- `transferCA()` — corporate-action-aware transfers with expected CAID

### Milestone 3: Cash Dividends
- Distribution contract, Merkle tree entitlements, pull-based claims

### Milestone 4: Stock Dividends
- Same Merkle/pull pattern, distributing additional ERC-20 tokens
