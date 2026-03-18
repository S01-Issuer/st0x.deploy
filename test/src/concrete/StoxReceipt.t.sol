// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {StoxReceipt} from "../../../src/concrete/StoxReceipt.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract StoxReceiptTest is Test {
    /// Constructor disables initializers on the implementation.
    function testConstructorDisablesInitializers() external {
        StoxReceipt impl = new StoxReceipt();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(abi.encode(address(1)));
    }
}
