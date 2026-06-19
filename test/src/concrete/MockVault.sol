// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {
    ICorporateActionsV1,
    ACTION_TYPE_STOCK_SPLIT_V1,
    BALANCE_MIGRATION_TYPES_MASK
} from "../../../src/interface/ICorporateActionsV1.sol";
import {CompletionFilter, NODE_NONE} from "../../../src/lib/LibCorporateActionNode.sol";
import {IReceiptManagerV2} from "rain-vats-0.1.6/src/interface/IReceiptManagerV2.sol";

/// @dev Mock vault combining `ICorporateActionsV1` (corporate-action read
/// surface) and `IReceiptManagerV2` (receipt transfer authorizer). The
/// receipt's base `_update` calls `s.manager.authorizeReceiptTransfer3(...)`
/// before applying the transfer, and our override reads multipliers via
/// `this.manager()` cast to `ICorporateActionsV1`. A single mock serving
/// both interfaces matches the real topology where the vault is a single
/// contract implementing both.
///
/// `IReceiptManagerV2` also requires `symbol()`, `decimals()` etc. via the
/// Receipt's `getVaultShareSymbol` helper. In tests we only call `balanceOf`
/// and `_update` paths that don't hit `uri()`, so the stub implementations
/// below are minimal.
contract MockVault is ICorporateActionsV1, IReceiptManagerV2 {
    error ReceiptTransferDenied();

    bytes[] internal splits; // splits[i-1] is the parameters blob for cursor i
    bool public denyTransfers;

    /// Authorize hook — allows or denies based on `denyTransfers`.
    function authorizeReceiptTransfer3(address, address, address, uint256[] memory, uint256[] memory)
        external
        view
        override
    {
        if (denyTransfers) revert ReceiptTransferDenied();
    }

    function setDenyTransfers(bool deny) external {
        denyTransfers = deny;
    }

    function addSplit(Float multiplier) external {
        splits.push(abi.encode(multiplier));
    }

    // ICorporateActionsV1

    function nextOfType(uint256 cursor, uint256 mask, CompletionFilter filter)
        external
        view
        override
        returns (uint256, uint256, uint64)
    {
        // Receipt rebase walks `BALANCE_MIGRATION_TYPES_MASK` (init |
        // stock-split). This mock holds only splits — no init node — so
        // walking that mask returns the same sequence as walking the
        // stock-split bit alone.
        require(mask == BALANCE_MIGRATION_TYPES_MASK, "mock: unexpected mask");
        require(filter == CompletionFilter.COMPLETED, "mock: unexpected filter");
        // Cursor 0 is the vault's bootstrap (identity); splits live at
        // 1..splits.length. The "no more nodes" sentinel is `NODE_NONE`,
        // matching the real vault's contract.
        if (cursor == NODE_NONE) {
            // Empty splits → no-more-nodes shape (NODE_NONE, 0, 0), matching
            // the cursor-walked-past-end branch below. Returning a non-zero
            // actionType for a NODE_NONE cursor is a contract violation
            // CodeRabbit caught — would let traversal tests pass against
            // states the real vault never produces.
            if (splits.length == 0) return (NODE_NONE, 0, 0);
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

    function scheduleCorporateAction(bytes32, uint64, bytes calldata) external pure override returns (uint256) {
        revert("mock");
    }

    function cancelCorporateAction(uint256) external pure override {
        revert("mock");
    }

    function completedActionCount() external view override returns (uint256) {
        return splits.length;
    }

    function latestActionOfType(uint256, CompletionFilter) external pure override returns (uint256, uint256, uint64) {
        revert("mock");
    }

    function earliestActionOfType(uint256, CompletionFilter) external pure override returns (uint256, uint256, uint64) {
        revert("mock");
    }

    function prevOfType(uint256, uint256, CompletionFilter) external pure override returns (uint256, uint256, uint64) {
        revert("mock");
    }

    /// Expose minimal IERC20Metadata surface that `Receipt.getVaultShareSymbol`
    /// calls via `IERC20Metadata(address(manager)).symbol()`. Not actually
    /// used in our tests (we never hit `uri()`), but the `_update` path may
    /// touch it if anything inspects name/symbol. Stubbed for safety.
    function symbol() external pure returns (string memory) {
        return "TEST";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function asset() external view returns (address) {
        return address(this);
    }
}
