// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";

/// @title LibProdDeployV1Test
/// @notice Verifies V1 creation bytecodes match compiled artifacts for
/// contracts that are unchanged between V1 and V2.
contract LibProdDeployV1Test is Test {
    /// StoxReceipt creation bytecode matches V1 constant.
    function testCreationBytecodeStoxReceipt() external view {
        assertEq(vm.getCode("StoxReceipt.sol:StoxReceipt"), LibProdDeployV1.PROD_STOX_RECEIPT_CREATION_BYTECODE_V1);
    }

    /// StoxReceiptVault creation bytecode matches V1 constant.
    function testCreationBytecodeStoxReceiptVault() external view {
        assertEq(
            vm.getCode("StoxReceiptVault.sol:StoxReceiptVault"),
            LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V1
        );
    }
}
