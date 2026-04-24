// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {CORPORATE_ACTION_STORAGE_LOCATION} from "src/lib/LibCorporateAction.sol";
import {CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION} from "src/lib/LibCorporateActionReceipt.sol";
import {ERC20_STORAGE_LOCATION} from "src/lib/LibERC20Storage.sol";
import {ERC1155_STORAGE_LOCATION} from "src/lib/LibERC1155Storage.sol";

/// @dev Pins that the four ERC-7201 namespaced storage roots used by the
/// corporate-actions stack are pairwise distinct. A collision would cause
/// two libraries to read/write the same slot, silently corrupting either
/// side's state.
contract StorageSlotDistinctnessTest is Test {
    function testPairwiseDistinct() external pure {
        assertTrue(CORPORATE_ACTION_STORAGE_LOCATION != CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION);
        assertTrue(CORPORATE_ACTION_STORAGE_LOCATION != ERC20_STORAGE_LOCATION);
        assertTrue(CORPORATE_ACTION_STORAGE_LOCATION != ERC1155_STORAGE_LOCATION);
        assertTrue(CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION != ERC20_STORAGE_LOCATION);
        assertTrue(CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION != ERC1155_STORAGE_LOCATION);
        assertTrue(ERC20_STORAGE_LOCATION != ERC1155_STORAGE_LOCATION);
    }
}
