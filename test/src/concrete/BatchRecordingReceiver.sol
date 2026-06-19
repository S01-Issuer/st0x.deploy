// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {StoxReceipt} from "../../../src/concrete/StoxReceipt.sol";

/// @dev Contract recipient that records its own balance per id observed
/// during `onERC1155BatchReceived`. Mirrors `RecordingReceiver` for the
/// batch path.
contract BatchRecordingReceiver {
    StoxReceipt public immutable RECEIPT;
    mapping(uint256 => uint256) public observedBalance;

    constructor(StoxReceipt receipt_) {
        RECEIPT = receipt_;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata ids, uint256[] calldata, bytes calldata)
        external
        returns (bytes4)
    {
        for (uint256 i = 0; i < ids.length; i++) {
            observedBalance[ids[i]] = RECEIPT.balanceOf(address(this), ids[i]);
        }
        return this.onERC1155BatchReceived.selector;
    }
}
