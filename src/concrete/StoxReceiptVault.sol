// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {OffchainAssetReceiptVault} from "rain.vats/concrete/vault/OffchainAssetReceiptVault.sol";
import {LibCorporateAction, ACTION_TYPE_STOCK_SPLIT} from "../lib/LibCorporateAction.sol";
import {CorporateActionNode, CompletionFilter, LibCorporateActionNode} from "../lib/LibCorporateActionNode.sol";
import {LibRebase} from "../lib/LibRebase.sol";
import {LibTotalSupply} from "../lib/LibTotalSupply.sol";
import {LibERC20Storage} from "../lib/LibERC20Storage.sol";
import {LibProdDeployV3} from "../lib/LibProdDeployV3.sol";

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
/// 1. **Balance rasterization** — rewriting `LibERC20Storage.getBalance(account)`
///    from its pre-rebase value to the post-rebase value.
/// 2. **Cursor advancement** — updating `accountMigrationCursor[account]` to
///    the index of the latest completed split this account has now seen.
///
/// For zero-balance accounts, (1) is a no-op but (2) is still load-bearing:
/// otherwise a subsequent mint or transfer-in would land at a stale cursor
/// and the next `balanceOf` read would erroneously re-apply completed
/// multipliers. See `LibRebase.migratedBalance` and the
/// `audit/2026-04-07-01/` post-mortem for the full reproduction of the bug
/// this prevents.
contract StoxReceiptVault is OffchainAssetReceiptVault {
    /// @notice Emitted when an account's stored balance is rasterized to the
    /// post-rebase basis and / or its migration cursor advances through
    /// completed corporate actions. Fires from `_update` via `_migrateAccount`,
    /// before the mint / burn / transfer delta is applied. Only fires when
    /// the stored balance actually changes; pure cursor-only advancements
    /// (zero-balance accounts) do not emit.
    /// @param account The account whose migration state changed.
    /// @param fromCursor The account's migration cursor before this migration
    /// (0 means never migrated). Corresponds to the 1-based index of the last
    /// completed corporate action this account had already seen.
    /// @param toCursor The account's migration cursor after this migration.
    /// @param oldBalance The account's **stored** balance before rasterization
    /// — i.e. the value returned by `LibERC20Storage.getBalance(account)` at
    /// the moment the migration starts, NOT the post-rebase effective balance.
    /// @param newBalance The account's **stored** balance after rasterization.
    /// For a single forward 2x split applied to a pre-rebase stored balance of
    /// 100, this is 200.
    event AccountMigrated(
        address indexed account, uint256 fromCursor, uint256 toCursor, uint256 oldBalance, uint256 newBalance
    );

    /// @notice Emitted when `_update` detects that one or more stock splits
    /// have passed their `effectiveTime` since the last `fold()`. Fires once
    /// per newly-effective split, **before** any account migration runs in
    /// the same transaction. This means every `AccountMigrated` event in the
    /// same transaction is guaranteed to follow the `CorporateActionEffective`
    /// event(s) for the split(s) that triggered it.
    ///
    /// Indexers can use this as a signal to update any balance-based logic
    /// or cached balances to post-rebase values. The `wasEffectiveAt`
    /// timestamp is (almost always) in the past — it records when the split
    /// was *scheduled* to take effect, not when the first transaction
    /// observed it. The difference is however many blocks elapsed between
    /// `effectiveTime` and this first touch.
    ///
    /// See `audit/2026-04-09-01/token-integration-analyzer.md` recommendation
    /// §10.8 and `docs/INTEGRATION.md` §Events for detailed integrator guidance.
    ///
    /// @param actionIndex The 1-based node index of the corporate action.
    /// @param actionType The bitmap action type (e.g. `ACTION_TYPE_STOCK_SPLIT`).
    /// @param wasEffectiveAt The `effectiveTime` recorded at schedule time.
    event CorporateActionEffective(uint256 indexed actionIndex, uint256 actionType, uint64 wasEffectiveAt);

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
        uint256 stored = LibERC20Storage.getBalance(account);
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        (uint256 balance,) = LibRebase.migratedBalance(stored, s.accountMigrationCursor[account]);
        return balance;
    }

    /// @notice Returns the effective total supply after applying every
    /// completed corporate action's multiplier on top of the per-cursor pot
    /// model tracked by `LibTotalSupply`. See `LibTotalSupply` for the full
    /// explanation of the per-pot walking recurrence.
    /// @return The effective total supply, consistent with the sum of
    /// `balanceOf` over all holders (the invariant upheld by per-account
    /// migration plus per-cursor pots).
    function totalSupply() public view virtual override returns (uint256) {
        return LibTotalSupply.effectiveTotalSupply();
    }

    /// @dev Bootstraps totalSupply tracking, emits CorporateActionEffective
    /// for any newly-past splits, migrates both sender and recipient, tracks
    /// mint/burn deltas, then calls super.
    function _update(address from, address to, uint256 amount) internal virtual override {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 prevLatest = s.totalSupplyLatestSplit;
        LibTotalSupply.fold();
        uint256 newLatest = s.totalSupplyLatestSplit;

        // Emit one event per newly-effective split. This fires BEFORE any
        // account migration so indexers see the split signal before any
        // per-account balance changes in the same transaction.
        if (newLatest != prevLatest) {
            _emitNewlyEffectiveSplits(prevLatest, newLatest);
        }

        _migrateAccount(from);
        _migrateAccount(to);

        if (from == address(0)) {
            LibTotalSupply.onMint(amount);
        } else if (to == address(0)) {
            LibTotalSupply.onBurn(amount);
        }

        super._update(from, to, amount);
    }

    /// @dev Migrate a single account through every completed split that has
    /// not yet been applied to it (i.e. completed split nodes whose index is
    /// past the account's current `accountMigrationCursor`). This both
    /// rasterizes the account's stored balance to the post-rebase basis and
    /// advances the cursor; for zero-balance accounts the balance rewrite is
    /// a no-op but the cursor advancement is still load-bearing — see
    /// `LibRebase.migratedBalance` and the 2026-04-07-01 audit post-mortem for
    /// the bug this prevents.
    ///
    /// `internal` (rather than `private`) so test harnesses derived from this
    /// contract can exercise the migration logic in isolation. The function is
    /// only ever called from this contract's `_update` override.
    function _migrateAccount(address account) internal {
        if (account == address(0)) return;

        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        uint256 currentCursor = s.accountMigrationCursor[account];
        uint256 storedBalance = LibERC20Storage.getBalance(account);

        (uint256 newBalance, uint256 newCursor) = LibRebase.migratedBalance(storedBalance, currentCursor);

        if (newCursor == currentCursor) return;

        s.accountMigrationCursor[account] = newCursor;

        if (newBalance != storedBalance) {
            LibERC20Storage.setBalance(account, newBalance);
            emit AccountMigrated(account, currentCursor, newCursor, storedBalance, newBalance);
        }

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

    /// @dev Walk from `prevLatest` to `newLatest` along the stock-split
    /// linked list and emit `CorporateActionEffective` for each node.
    /// Called from `_update` between `fold()` and `_migrateAccount()` so
    /// the event fires before any per-account balance changes.
    function _emitNewlyEffectiveSplits(uint256 prevLatest, uint256 newLatest) internal {
        uint256 nodeIndex =
            LibCorporateActionNode.nextOfType(prevLatest, ACTION_TYPE_STOCK_SPLIT, CompletionFilter.COMPLETED);

        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();

        while (nodeIndex != 0) {
            CorporateActionNode storage node = s.nodes[nodeIndex];
            emit CorporateActionEffective(nodeIndex, node.actionType, node.effectiveTime);
            if (nodeIndex == newLatest) break;
            nodeIndex =
                LibCorporateActionNode.nextOfType(nodeIndex, ACTION_TYPE_STOCK_SPLIT, CompletionFilter.COMPLETED);
        }
    }
}
