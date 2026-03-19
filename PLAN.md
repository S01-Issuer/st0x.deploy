<!-- SPDX-License-Identifier: LicenseRef-DCL-1.0 -->
<!-- SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd -->

# Corporate Action Registry — Implementation Plan

## Status: In Progress

## Overview

Add a corporate action registry to st0x.deploy that enables onchain scheduling
and execution of corporate actions against StoxReceiptVault tokens. The registry
exposes onchain readable state so downstream protocols can query and react to
upcoming and in-progress corporate actions.

Full spec: `~/.openclaw/workspace/corporate-action-registry-spec.md`

---

## Milestone 1: Registry + Name/Symbol Changes

### PR 1: CorporateActionRegistry contract
- [ ] `src/concrete/CorporateActionRegistry.sol`
  - Token-agnostic, standalone contract
  - `schedule(token, actionType, data, effectiveTime)` — schedule future action
  - `execute(token, actionType, number)` — execute after effective time
  - Action lifecycle: SCHEDULED → IN_PROGRESS → COMPLETE
  - Namespaced per-token, per-action-type sequential IDs (counters)
  - Read interface: `getAction()`, `getCounter()`, `getActionState()`
  - Events: `CorporateActionScheduled`, `CorporateActionExecuted`
  - Authorisation via token's authoriser (registry must hold the relevant role)
- [ ] Error types in `src/error/ErrCorporateActionRegistry.sol`
- [ ] Interface in `src/interface/ICorporateActionRegistry.sol`
- [ ] Tests: registry lifecycle in isolation (schedule, time travel, execute, reverts)

### PR 2: StoxAuthorizer (extends OffchainAssetReceiptVaultAuthorizerV1)
- [ ] `src/concrete/authorize/StoxAuthorizer.sol`
  - Extends `OffchainAssetReceiptVaultAuthorizerV1` from ethgild
  - Adds `UPDATE_NAME_SYMBOL` permission + `UPDATE_NAME_SYMBOL_ADMIN` role
  - Future: `REBASE` permission (not this milestone)
  - Same RBAC pattern as existing permissions
  - `initialAdmin` gets all new admin roles on init
- [ ] Tests: role grants, authorize calls, unauthorised reverts

### PR 3: StoxReceiptVault name/symbol override + CAID
- [ ] Modify `src/concrete/StoxReceiptVault.sol`
  - ERC-7201 namespaced storage for name/symbol overrides + current CAID
  - `name()` / `symbol()` overrides (fall through to super if not set)
  - `updateNameSymbol(actionType, number, newName, newSymbol)` — gated by authoriser
  - `_computeCAID(actionType, number)` — hashes `msg.sender + actionType + number`
  - Stores CAID on update so it's locally readable without registry callback
- [ ] e2e tests: deploy registry + vault + StoxAuthorizer, grant roles, schedule
  name/symbol change, advance time, execute, verify name()/symbol() updated,
  verify CAID set, verify wrapper auto-reflects new name
- [ ] Revert cases: execute before effective time, double execute, unauthorised,
  wrong CAID

---

## Future Milestones (not yet scoped)

### Milestone 2: Rebasing / Stock Splits
- Rebase multiplier storage + lazy migration in StoxReceiptVault
- `_update()` hook with rasterize-then-update pattern
- `applyRebase()` gated by authoriser
- ERC-1155 receipt rebasing in StoxReceipt
- `REBASE` permission in StoxAuthorizer
- `transferCA()` — corporate-action-aware transfers with expected CAID

### Milestone 3: Cash Dividends
- Distribution contract, Merkle tree entitlements, pull-based claims

### Milestone 4: Stock Dividends
- Same Merkle/pull pattern, distributing additional ERC-20 tokens
