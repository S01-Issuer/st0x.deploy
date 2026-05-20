// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {OffchainAssetReceiptVault} from "rain-vats-0.1.5/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {IAuthorizeV1} from "rain-vats-0.1.5/src/interface/IAuthorizeV1.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibCorporateAction, SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../lib/LibCorporateAction.sol";
import {LibRebase} from "../lib/LibRebase.sol";
import {LibTotalSupply} from "../lib/LibTotalSupply.sol";
import {LibERC20Storage} from "../lib/LibERC20Storage.sol";
import {LibProdDeployV3} from "../lib/LibProdDeployV3.sol";
import {AuthorizerMissingCorporateActionAdmin} from "../error/ErrCorporateAction.sol";

/// @title StoxReceiptVault
/// @notice An OffchainAssetReceiptVault that supports corporate actions such
/// as stock splits. Balances automatically reflect any pending corporate
/// action multipliers.
///
/// Migration is lazy: each account's stored balance is rasterized to the
/// current rebase version on first interaction (transfer, mint, burn).
/// Balance writes go directly to OZ's ERC20 storage via assembly — no
/// mint/burn, no Transfer events, no totalSupply side effects.
///
/// totalSupply uses per-cursor pots so that account migrations genuinely
/// improve precision. See LibTotalSupply for the full explanation.
///
/// @dev "Migration" here covers two distinct operations that usually happen
/// together but MUST be treated separately:
/// 1. **Balance rasterization** — rewriting `LibERC20Storage.underlyingBalance(account)`
///    from its pre-rebase value to the post-rebase value.
/// 2. **Cursor advancement** — updating `accountMigrationCursor[account]` to
///    the index of the latest completed split this account has now seen.
///
/// For zero-balance accounts, (1) is a no-op but (2) still matters: without
/// it a subsequent mint or transfer-in would land at a stale cursor and the
/// next `balanceOf` read would erroneously re-apply completed multipliers to
/// a balance that was already written at the post-rebase basis, silently
/// inflating the recipient's balance. See `LibRebase.migratedBalance` and
/// its zero-balance regression tests.
contract StoxReceiptVault is OffchainAssetReceiptVault {
    /// @notice Emitted whenever `migrateAccount` advances an account's
    /// migration cursor. The cursor itself is storage state, so the event
    /// fires on every cursor advance regardless of whether
    /// `oldBalance == newBalance`. Fires from `_update` via
    /// `migrateAccount`, before the mint / burn / transfer delta is
    /// applied.
    /// @param account The account whose migration state changed.
    /// @param fromActionId The action id the account's cursor was at
    /// before this migration. The default 0 corresponds to the bootstrap
    /// node (idx 0) — every fresh holder starts there because the cursor
    /// mapping defaults to 0 and bootstrap is identity for splits, so "no
    /// migration applied" and "migrated through the identity bootstrap"
    /// are the same state.
    /// @param toActionId The action id the account's cursor is at
    /// after this migration.
    /// @param oldBalance The account's **stored** balance before rasterization
    /// — i.e. the value returned by `LibERC20Storage.underlyingBalance(account)` at
    /// the moment the migration starts, NOT the post-rebase effective balance.
    /// @param newBalance The account's **stored** balance after rasterization.
    /// For a single forward 2x split applied to a pre-rebase stored balance of
    /// 100, this is 200.
    event AccountMigrated(
        address indexed account, uint256 fromActionId, uint256 toActionId, uint256 oldBalance, uint256 newBalance
    );

    /// @notice Returns `account`'s ERC20 balance including any pending rebase
    /// multipliers from completed corporate actions. Does NOT mutate state —
    /// if the account's stored balance is stale relative to the latest
    /// completed split, this call computes the rebased value on the fly and
    /// returns it. The actual rasterization happens lazily on the next
    /// `_update` touch.
    /// @param account The account to query.
    /// @return The effective balance after applying all completed stock splits
    /// on top of the account's last-migrated cursor.
    function balanceOf(address account) public view virtual override returns (uint256) {
        uint256 stored = LibERC20Storage.underlyingBalance(account);
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        // The second return value is the new cursor — intentionally discarded
        // here because `balanceOf` is a pure read that must not mutate state;
        // the cursor advancement happens on the next `_update` touch via
        // `migrateAccount`.
        // slither-disable-next-line unused-return
        (uint256 balance,) = LibRebase.migratedBalance(stored, s.accountMigrationCursor[account]);
        return balance;
    }

    /// @notice Returns the effective total supply after applying every
    /// completed corporate action's multiplier on top of the per-cursor pot
    /// model tracked by `LibTotalSupply`. See `LibTotalSupply` for the full
    /// explanation of the per-pot walking recurrence.
    /// @return An upper bound on `sum(balanceOf)` that converges to exact
    /// equality once every holder sharing a pre-split cursor has migrated
    /// through the split. The walk applies each multiplier to the aggregate
    /// pot, so for fractional multipliers `trunc(Σ aᵢ * m) ≥ Σ trunc(aᵢ * m)`
    /// — the gap is the per-account truncation dust, and it disappears as
    /// accounts migrate.
    function totalSupply() public view virtual override returns (uint256) {
        return LibTotalSupply.effectiveTotalSupply();
    }

    /// @dev Bootstraps totalSupply tracking, migrates both sender and
    /// recipient, calls super, then tracks mint/burn deltas in the pot.
    /// `onMint` / `onBurn` run AFTER `super._update` so OZ's own
    /// validation (e.g. `ERC20InsufficientBalance` on an over-burn)
    /// fires first. If these ran before super, a lone-holder over-burn
    /// at `latestSplit` would underflow the pot with a raw arithmetic
    /// panic rather than surfacing OZ's intended error.
    function _update(address from, address to, uint256 amount) internal virtual override {
        LibTotalSupply.fold();

        migrateAccount(from);
        migrateAccount(to);

        super._update(from, to, amount);

        if (from == address(0)) {
            LibTotalSupply.onMint(amount);
        } else if (to == address(0)) {
            LibTotalSupply.onBurn(amount);
        }
    }

    /// @dev Migrate a single account through every completed split that has
    /// not yet been applied to it (i.e. completed split nodes whose index is
    /// past the account's current `accountMigrationCursor`). This both
    /// rasterizes the account's stored balance to the post-rebase basis and
    /// advances the cursor; for zero-balance accounts the balance rewrite is
    /// a no-op but the cursor advancement still matters — see
    /// `LibRebase.migratedBalance` and its zero-balance regression tests for
    /// the bug this prevents.
    ///
    /// `internal` (rather than `private`) so test harnesses derived from this
    /// contract can exercise the migration logic in isolation. The function is
    /// only ever called from this contract's `_update` override.
    function migrateAccount(address account) internal {
        if (account == address(0)) return;

        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 currentCursor = s.accountMigrationCursor[account];
        uint256 storedBalance = LibERC20Storage.underlyingBalance(account);

        (uint256 newBalance, uint256 newCursor) = LibRebase.migratedBalance(storedBalance, currentCursor);

        if (newCursor == currentCursor) return;

        s.accountMigrationCursor[account] = newCursor;

        // Skip the SSTORE when the rasterized balance is unchanged.
        if (newBalance != storedBalance) {
            LibERC20Storage.setUnderlyingBalance(account, newBalance);
        }
        emit AccountMigrated(account, currentCursor, newCursor, storedBalance, newBalance);

        LibTotalSupply.onAccountMigrated(currentCursor, storedBalance, newCursor, newBalance);
    }

    /// @notice Routes calls with non-matching selectors to the corporate actions
    /// facet via delegatecall. The facet address is hardcoded to its
    /// deterministic Zoltu deploy address from `LibProdDeployV3`.
    ///
    /// @dev Baking the facet address into the vault implementation bytecode
    /// means upgrading the facet requires upgrading the vault implementation
    /// too. This matches the existing pattern where deployers hardcode beacon
    /// addresses (Option 1 from S01-Issuer/st0x.deploy#70).
    ///
    /// Plain ETH transfers with empty calldata hit `receive()`, not this
    /// function, so refunds continue to work without going through delegatecall.
    ///
    /// **Trust model.** The corporate-actions facet calls the vault's
    /// `authorizer()` for any state-mutating entry point (schedule, cancel).
    /// The authorizer is the canonical permission boundary — set by the
    /// vault owner during initialization. A compromised authorizer can
    /// already grant or deny any permission, so re-entrancy through the
    /// authorizer adds no new attack surface beyond what a sequence of
    /// authorized calls would already permit. No reentrancy guard is
    /// applied here on that basis. See `StoxCorporateActionsFacet`'s
    /// per-function comments for the per-method argument that the
    /// linked-list and cursor writes remain consistent under re-entry.
    fallback() external payable virtual override {
        address facet = LibProdDeployV3.STOX_CORPORATE_ACTIONS_FACET;
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch success
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /// @notice Reject authorizers that don't configure admin hierarchies
    /// for the corporate-action roles. Without an explicit admin, the
    /// role's admin resolves to the unassigned `DEFAULT_ADMIN_ROLE` and
    /// the role becomes permanently ungrantable — silently disabling
    /// corporate actions and drifting the vault away from the underlying
    /// off-chain asset. Surfaces the misconfiguration at the pairing
    /// point so the operator hears about it immediately, not on the
    /// first attempted `scheduleCorporateAction` call months later.
    ///
    /// Reverts with `AuthorizerMissingCorporateActionAdmin` if either
    /// `SCHEDULE_CORPORATE_ACTION` or `CANCEL_CORPORATE_ACTION` resolves
    /// to `DEFAULT_ADMIN_ROLE` on the supplied authorizer. Requires the
    /// authorizer to implement `IAccessControl`.
    /// @inheritdoc OffchainAssetReceiptVault
    function setAuthorizer(IAuthorizeV1 newAuthorizer) public override {
        bytes32 scheduleAdmin = IAccessControl(address(newAuthorizer)).getRoleAdmin(SCHEDULE_CORPORATE_ACTION);
        if (scheduleAdmin == bytes32(0)) {
            revert AuthorizerMissingCorporateActionAdmin(address(newAuthorizer), SCHEDULE_CORPORATE_ACTION);
        }
        bytes32 cancelAdmin = IAccessControl(address(newAuthorizer)).getRoleAdmin(CANCEL_CORPORATE_ACTION);
        if (cancelAdmin == bytes32(0)) {
            revert AuthorizerMissingCorporateActionAdmin(address(newAuthorizer), CANCEL_CORPORATE_ACTION);
        }
        super.setAuthorizer(newAuthorizer);
    }
}
