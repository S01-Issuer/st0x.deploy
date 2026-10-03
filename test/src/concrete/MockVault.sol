// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {MockCorporateActionsReadBase} from "../lib/MockCorporateActionsReadBase.sol";
import {IReceiptManagerV2} from "rain-vats-0.2.1/src/interface/IReceiptManagerV2.sol";

/// @dev Mock vault combining `ICorporateActionsV1` (corporate-action read
/// surface, inherited from `MockCorporateActionsReadBase`) and
/// `IReceiptManagerV2` (receipt transfer authorizer), as the real vault
/// implements both. The receipt's base `_update` calls
/// `s.manager.authorizeReceiptTransfer3(...)` before applying the transfer,
/// and the override reads multipliers via `this.manager()` cast to
/// `ICorporateActionsV1`.
contract MockVault is MockCorporateActionsReadBase, IReceiptManagerV2 {
    error ReceiptTransferDenied();

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

    /// Minimal IERC20Metadata surface that `Receipt.getVaultShareSymbol`
    /// calls via `IERC20Metadata(address(manager)).symbol()`.
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
