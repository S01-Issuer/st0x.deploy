// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {StoxReceipt} from "../../../src/concrete/StoxReceipt.sol";

/// @dev Contract recipient that records the sender and receiver balances
/// observed during its `onERC1155Received` callback. Used to pin the
/// invariant that receive hooks fire post-migration, post-transfer.
contract RecordingReceiver {
    StoxReceipt public immutable RECEIPT;
    address public immutable ALICE;
    uint256 public observedAliceBalance;
    uint256 public observedRecvBalance;

    constructor(StoxReceipt receipt_, address alice_) {
        RECEIPT = receipt_;
        ALICE = alice_;
    }

    function onERC1155Received(address, address, uint256 id, uint256, bytes calldata) external returns (bytes4) {
        observedAliceBalance = RECEIPT.balanceOf(ALICE, id);
        observedRecvBalance = RECEIPT.balanceOf(address(this), id);
        return this.onERC1155Received.selector;
    }
}
