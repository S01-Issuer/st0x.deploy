// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {StoxReceipt} from "src/concrete/StoxReceipt.sol";
import {Receipt as ReceiptContract} from "ethgild/concrete/receipt/Receipt.sol";
import {Test} from "forge-std/Test.sol";

contract StoxReceiptTest is Test {
    /// We can check the StoxReceipt is just a vanilla Receipt.
    function testStoxReceiptImplementation() external {
        ReceiptContract receipt = new ReceiptContract();
        StoxReceipt stoxReceipt = new StoxReceipt();
        assertEq(address(receipt).codehash, address(stoxReceipt).codehash);
    }
}
