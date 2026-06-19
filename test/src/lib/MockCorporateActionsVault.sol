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

/// @dev Mock vault exposing only the subset of `ICorporateActionsV1` that
/// `LibReceiptRebase` consumes (`nextOfType` + `getActionParameters`). Tests
/// preload the mock with a list of completed stock split multipliers, and
/// the receipt rebase walks it exactly as if it were a real vault.
///
/// The mock assigns cursor indices 1..n to the preloaded multipliers,
/// mirroring the vault's storage layout post-bootstrap: index 0 is the
/// real bootstrap node (which the mock does not model — receipt rebase
/// treats it as identity), indices 1..n are the stock splits in
/// effective-time order. `nextOfType` returns the next index;
/// `getActionParameters` returns the stored bytes. `NODE_NONE` is the
/// "no more nodes" sentinel matching the real vault's contract.
contract MockCorporateActionsVault is ICorporateActionsV1 {
    bytes[] internal splits; // splits[i-1] is the parameters blob for cursor i

    function addSplit(Float multiplier) external {
        splits.push(abi.encode(multiplier));
    }

    function addSplitRaw(bytes memory parameters) external {
        splits.push(parameters);
    }

    function splitCount() external view returns (uint256) {
        return splits.length;
    }

    // -----------------------------------------------------------------------
    // ICorporateActionsV1 — only the bits LibReceiptRebase calls

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
            // Receipt rebase callers never pass NODE_NONE — they always
            // pass the receipt-side cursor — but keep the contract honest.
            return (splits.length == 0 ? NODE_NONE : 1, ACTION_TYPE_STOCK_SPLIT_V1, 1);
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

    // Unused ICorporateActionsV1 surface — revert to surface misuse.
    function scheduleCorporateAction(bytes32, uint64, bytes calldata) external pure override returns (uint256) {
        revert("mock: not implemented");
    }

    function cancelCorporateAction(uint256) external pure override {
        revert("mock: not implemented");
    }

    function completedActionCount() external view override returns (uint256) {
        return splits.length;
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
}
