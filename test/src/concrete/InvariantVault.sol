// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/token/ERC20/ERC20Upgradeable.sol";
import {LibCorporateAction} from "../../../src/lib/LibCorporateAction.sol";
import {ACTION_TYPE_STOCK_SPLIT_V1} from "../../../src/interface/ICorporateActionsV1.sol";
import {LibERC20Storage} from "../../../src/lib/LibERC20Storage.sol";
import {LibTotalSupply} from "../../../src/lib/LibTotalSupply.sol";
import {
    CorporateActionNode,
    CompletionFilter,
    LibCorporateActionNode,
    NODE_NONE
} from "../../../src/lib/LibCorporateActionNode.sol";
import {LibTestCorporateAction} from "../../lib/LibTestCorporateAction.sol";

/// @dev Auth-bypassed vault subclass used by the invariant harness. Mirrors
/// the production `StoxReceiptVault._update` flow exactly, only skipping the
/// `OffchainAssetReceiptVault` authorizer/freeze middle layer — the migration
/// semantics under test live entirely in `StoxReceiptVault` and the libraries
/// it calls. Also exposes the internal cursor / split state so invariants can
/// read it.
contract InvariantVault is StoxReceiptVault {
    function _update(address from, address to, uint256 amount) internal override {
        LibTotalSupply.fold();

        migrateAccount(from);
        migrateAccount(to);

        ERC20Upgradeable._update(from, to, amount);

        if (from == address(0)) {
            LibTotalSupply.onMint(amount);
        } else if (to == address(0)) {
            LibTotalSupply.onBurn(amount);
        }
    }

    function publicUpdate(address from, address to, uint256 amount) external {
        _update(from, to, amount);
    }

    function publicSchedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters)
        external
        returns (uint256)
    {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function publicCancel(uint256 actionIndex) external {
        LibCorporateAction.cancel(actionIndex);
    }

    function migrationCursor(address account) external view returns (uint256) {
        return LibCorporateAction.getStorage().accountMigrationCursor[account];
    }

    function totalSupplyLatestCursor() external view returns (uint256) {
        return LibCorporateAction.getStorage().totalSupplyLatestCursor;
    }

    function listHead() external view returns (uint256) {
        return LibTestCorporateAction.head();
    }

    function listTail() external view returns (uint256) {
        return LibTestCorporateAction.tail();
    }

    function getNode(uint256 index) external view returns (CorporateActionNode memory) {
        return LibCorporateAction.getStorage().nodes[index];
    }

    function nodesLength() external view returns (uint256) {
        return LibCorporateAction.getStorage().nodes.length;
    }

    function rawStoredBalance(address account) external view returns (uint256) {
        return LibERC20Storage.underlyingBalance(account);
    }

    /// @dev Whether any stock split in the list has reached its effective
    /// time. `effectiveTotalSupply` applies multipliers once this is true
    /// even if `fold()` has not yet been called to update
    /// `totalSupplyLatestCursor`, so invariants that depend on the
    /// no-multiplier regime must gate on this rather than
    /// `totalSupplyLatestCursor == 0`.
    function hasCompletedSplit() external view returns (bool) {
        return LibCorporateActionNode.nextOfType(NODE_NONE, ACTION_TYPE_STOCK_SPLIT_V1, CompletionFilter.COMPLETED)
            != NODE_NONE;
    }

    // -----------------------------------------------------------------------
    // ICorporateActionsV1 read surface — forwarded directly to the libraries
    // so the receipt contract can read stock split multipliers cross-contract
    // without a facet delegatecall router.
    //
    // Only the subset LibReceiptRebase actually consumes is implemented; the
    // other traversal getters are omitted because the receipt never calls
    // them. These are view-only; no migration or authorization logic needed.

    function nextOfType(uint256 cursor, uint256 mask, CompletionFilter filter)
        external
        view
        returns (uint256, uint256, uint64)
    {
        uint256 nextCursor = LibCorporateActionNode.nextOfType(cursor, mask, filter);
        if (nextCursor == NODE_NONE) {
            return (nextCursor, 0, 0);
        }
        CorporateActionNode storage node = LibCorporateAction.getStorage().nodes[nextCursor];
        return (nextCursor, node.actionType, node.effectiveTime);
    }

    function getActionParameters(uint256 cursor) external view returns (bytes memory) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        require(cursor != NODE_NONE && cursor < s.nodes.length, "InvariantVault: action does not exist");
        return s.nodes[cursor].parameters;
    }

    // -----------------------------------------------------------------------
    // IReceiptManagerV2.authorizeReceiptTransfer3 — no-op override (always
    // allows the transfer) so the receipt's base `_update` path can run in
    // the invariant harness without needing an ethgild authorizer wired in.
    // The real ethgild vault derives a multi-layered auth decision here;
    // our invariant test doesn't care about auth correctness, only the
    // rebase math.

    function authorizeReceiptTransfer3(address, address, address, uint256[] memory, uint256[] memory)
        public
        pure
        override
    {}
}
