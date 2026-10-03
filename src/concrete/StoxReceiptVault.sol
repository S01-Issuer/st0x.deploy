// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {OffchainAssetReceiptVault} from "rain-vats-0.2.1/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {IAuthorizeV1} from "rain-vats-0.2.1/src/interface/IAuthorizeV1.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibCorporateAction, SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../lib/LibCorporateAction.sol";
import {LibRebase} from "../lib/LibRebase.sol";
import {LibTotalSupply} from "../lib/LibTotalSupply.sol";
import {LibERC20Storage} from "../lib/LibERC20Storage.sol";
import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {AuthorizerMissingCorporateActionAdmin} from "../error/ErrCorporateAction.sol";

/// @title StoxReceiptVault
/// @notice An OffchainAssetReceiptVault that supports corporate actions such
/// as stock splits. Balances automatically reflect any pending corporate
/// action multipliers.
///
/// Migration is lazy: each account's stored balance is rasterized to the
/// current rebase version on first interaction (transfer, mint, burn).
/// Balance writes go directly to OZ's ERC20 storage via assembly, with no
/// Transfer events.
///
/// totalSupply uses per-cursor pots; see `LibTotalSupply`.
///
/// @dev "Migration" here covers two operations:
/// 1. **Balance rasterization**: rewriting `LibERC20Storage.underlyingBalance(account)`
///    from its pre-rebase value to the post-rebase value.
/// 2. **Cursor advancement**: updating `accountMigrationCursor[account]` to
///    the index of the latest completed split this account has now seen.
///
/// For zero-balance accounts, (1) is a no-op and (2) still happens, so a
/// later mint or transfer-in lands at the current cursor rather than a stale
/// one that would re-apply completed multipliers on the next `balanceOf`
/// read. See `LibRebase.migratedBalance`.
contract StoxReceiptVault is OffchainAssetReceiptVault {
    /// @notice Emitted whenever `migrateAccount` advances an account's
    /// migration cursor. The cursor itself is storage state, so the event
    /// fires on every cursor advance regardless of whether
    /// `oldBalance == newBalance`. Fires from `_update` via
    /// `migrateAccount`, before the mint / burn / transfer delta is
    /// applied.
    /// @param account The account whose migration state changed.
    /// @param fromActionId The action id the account's cursor was at
    /// before this migration. The default 0 is the bootstrap node (idx 0),
    /// where every fresh holder starts.
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
        // The second return value is the new cursor, discarded because
        // `balanceOf` is a read; cursor advancement happens on the next
        // `_update` via `migrateAccount`.
        // slither-disable-next-line unused-return
        (uint256 balance,) = LibRebase.migratedBalance(stored, s.accountMigrationCursor[account]);
        return balance;
    }

    /// @notice Returns the effective total supply after applying every
    /// completed corporate action's multiplier on top of the per-cursor pots
    /// tracked by `LibTotalSupply`.
    /// @return An upper bound on `sum(balanceOf)` that converges to exact
    /// equality once every holder sharing a pre-split cursor has migrated
    /// through the split. The walk applies each multiplier to the aggregate
    /// pot, so for fractional multipliers `trunc(Σ aᵢ * m) ≥ Σ trunc(aᵢ * m)`;
    /// the gap is the per-account truncation dust, which disappears as
    /// accounts migrate.
    function totalSupply() public view virtual override returns (uint256) {
        return LibTotalSupply.effectiveTotalSupply();
    }

    /// @dev Folds the totalSupply cursor, migrates both sender and recipient,
    /// calls super, then tracks mint/burn deltas in the pot. `onMint` /
    /// `onBurn` run after `super._update` so OZ's own validation (e.g.
    /// `ERC20InsufficientBalance` on an over-burn) fires first rather than
    /// a pot underflow panic.
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
    /// not yet been applied to it (completed split nodes whose index is past
    /// the account's current `accountMigrationCursor`). This both rasterizes
    /// the account's stored balance to the post-rebase basis and advances
    /// the cursor; for zero-balance accounts the balance rewrite is a no-op
    /// and the cursor still advances.
    ///
    /// `internal` so test harnesses derived from this contract can call it
    /// directly. Only called from this contract's `_update` override.
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

            // Rebasing rewrites `_balances` directly, so apply the same delta
            // to OZ's own `_totalSupply` accumulator and preserve its
            // `_totalSupply == Σ _balances` invariant. The raw slot is not the
            // reported supply (`totalSupply()` above is
            // `LibTotalSupply.effectiveTotalSupply()`) and the pot accounting
            // in `onAccountMigrated` below is untouched by this write, but
            // OZ's `_update` still subtracts from the raw slot unchecked on
            // burn and adds to it checked on mint; see
            // `LibERC20Storage.applyBalanceDeltaToTotalSupply`.
            LibERC20Storage.applyBalanceDeltaToTotalSupply(storedBalance, newBalance);
        }
        emit AccountMigrated(account, currentCursor, newCursor, storedBalance, newBalance);

        LibTotalSupply.onAccountMigrated(currentCursor, storedBalance, newCursor, newBalance);
    }

    /// @notice Routes calls with non-matching selectors to the corporate actions
    /// facet via delegatecall. The facet address is hardcoded to its
    /// deterministic Zoltu deploy address from `LibProdDeployCurrent`.
    ///
    /// @dev The facet address is baked into the vault implementation
    /// bytecode, so upgrading the facet requires upgrading the vault
    /// implementation too.
    ///
    /// Plain ETH transfers with empty calldata hit `receive()`, not this
    /// function.
    ///
    /// The corporate-actions facet calls the vault's `authorizer()` for every
    /// state-mutating entry point (schedule, cancel). No reentrancy guard is
    /// applied: re-entry through the authorizer can do nothing a sequence of
    /// authorized calls could not.
    fallback() external payable virtual override {
        address facet = LibProdDeployCurrent.STOX_CORPORATE_ACTIONS_FACET;
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch success
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /// @notice Reject authorizers without an admin for the corporate-action
    /// roles. A role whose admin resolves to the unassigned
    /// `DEFAULT_ADMIN_ROLE` is ungrantable.
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
