// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {
    ICorporateActionsV1,
    ACTION_TYPE_STOCK_SPLIT_V1,
    BALANCE_MIGRATION_TYPES_MASK
} from "src/interface/ICorporateActionsV1.sol";
import {CompletionFilter, NODE_NONE} from "src/lib/LibCorporateActionNode.sol";

/// @dev Shared read-subset base for the corporate-action test mocks. Exposes
/// only the slice of `ICorporateActionsV1` that the receipt/share rebase walks
/// consume (`nextOfType` + `getActionParameters` + `completedActionCount`),
/// backed by a preloaded list of completed stock split multipliers. Tests push
/// multipliers via `addSplit`; the walk treats them exactly as if they were a
/// real vault's completed stock-split nodes.
///
/// Cursor indices 1..n are assigned to the preloaded multipliers, mirroring the
/// vault's storage layout post-bootstrap: index 0 is the real bootstrap node
/// (identity, not modelled here — rebase treats it as identity), indices 1..n
/// are the stock splits in effective-time order. `nextOfType` returns the next
/// index; `getActionParameters` returns the stored bytes. `NODE_NONE` is the
/// "no more nodes" sentinel matching the real vault's contract.
///
/// The remaining `ICorporateActionsV1` surface is unused by the rebase walk and
/// reverts to surface any accidental call. Concrete mocks extend this base with
/// their own extra surface (e.g. the receipt-manager authorizer, or raw-blob
/// injection helpers).
abstract contract MockCorporateActionsReadBase is ICorporateActionsV1 {
    bytes[] internal splits; // splits[i-1] is the parameters blob for cursor i

    function addSplit(Float multiplier) external {
        splits.push(abi.encode(multiplier));
    }

    // -----------------------------------------------------------------------
    // ICorporateActionsV1 — only the bits the rebase walk calls

    function nextOfType(uint256 cursor, uint256 mask, CompletionFilter filter)
        external
        view
        override
        returns (uint256, uint256, uint64)
    {
        // Receipt rebase walks `BALANCE_MIGRATION_TYPES_MASK` (init |
        // stock-split). This mock holds only splits — no init node — so
        // walking that mask returns the same sequence as walking the
        // stock-split bit alone. Pin the mask to the production mask;
        // any other request fails loud.
        require(mask == BALANCE_MIGRATION_TYPES_MASK, "mock: unexpected mask");
        require(filter == CompletionFilter.COMPLETED, "mock: unexpected filter");

        // Cursor convention matches the real vault post-bootstrap: 0 is
        // the bootstrap node (identity, not modelled by this mock); splits
        // live at 1..splits.length. The walk hops from `cursor` to
        // `cursor + 1`, returning `NODE_NONE` once the next index would
        // run off the end.
        if (cursor == NODE_NONE) {
            // Receipt rebase callers never pass NODE_NONE — they always pass
            // the receipt-side cursor — but keep the contract honest: an empty
            // list yields the (NODE_NONE, 0, 0) no-match shape the real vault
            // returns, not a null cursor paired with a live
            // actionType/effectiveTime. Returning a non-zero actionType for a
            // NODE_NONE cursor is a contract violation that would let traversal
            // tests pass against states the real vault never produces.
            if (splits.length == 0) {
                return (NODE_NONE, 0, 0);
            }
            return (1, ACTION_TYPE_STOCK_SPLIT_V1, 1);
        }
        uint256 candidate = cursor + 1;
        if (candidate > splits.length) {
            return (NODE_NONE, 0, 0);
        }
        return (candidate, ACTION_TYPE_STOCK_SPLIT_V1, 1);
    }

    function getActionParameters(uint256 cursor) external view override returns (bytes memory) {
        require(cursor >= 1 && cursor <= splits.length, "mock: cursor out of range");
        return splits[cursor - 1];
    }

    function completedActionCount() external view override returns (uint256) {
        return splits.length;
    }

    // Unused ICorporateActionsV1 surface — revert to surface misuse.
    function scheduleCorporateAction(bytes32, uint64, bytes calldata) external pure override returns (uint256) {
        revert("mock: not implemented");
    }

    function cancelCorporateAction(uint256) external pure override {
        revert("mock: not implemented");
    }

    function latestActionOfType(uint256, CompletionFilter) external pure override returns (uint256, uint256, uint64) {
        revert("mock: not implemented");
    }

    function earliestActionOfType(uint256, CompletionFilter) external pure override returns (uint256, uint256, uint64) {
        revert("mock: not implemented");
    }

    function prevOfType(uint256, uint256, CompletionFilter) external pure override returns (uint256, uint256, uint64) {
        revert("mock: not implemented");
    }

    function cumulativeBalanceMultiplierSinceGenesis() external pure override returns (Float) {
        revert("mock: not implemented");
    }
}
