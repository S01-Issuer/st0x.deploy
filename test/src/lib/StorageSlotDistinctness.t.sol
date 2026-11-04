// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {CORPORATE_ACTION_STORAGE_LOCATION} from "src/lib/LibCorporateAction.sol";
import {CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION} from "src/lib/LibCorporateActionReceipt.sol";
import {ERC20_STORAGE_LOCATION} from "src/lib/LibERC20Storage.sol";
import {ERC1155_STORAGE_LOCATION} from "src/lib/LibERC1155Storage.sol";
import {UNDERLYING_STORAGE_LOCATION} from "../../../src/lib/LibUnderlying.sol";
import {ASSET_ID_STORAGE_LOCATION} from "../../../src/lib/LibAssetId.sol";

/// @dev Pins that the six ERC-7201 namespaced storage roots used by the
/// corporate-actions stack, the underlying identity and the asset id, and
/// OZ's `Initializable` root the facet reads, are pairwise distinct. A collision would cause
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
        assertTrue(UNDERLYING_STORAGE_LOCATION != CORPORATE_ACTION_STORAGE_LOCATION);
        assertTrue(UNDERLYING_STORAGE_LOCATION != CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION);
        assertTrue(UNDERLYING_STORAGE_LOCATION != ERC20_STORAGE_LOCATION);
        assertTrue(UNDERLYING_STORAGE_LOCATION != ERC1155_STORAGE_LOCATION);
        bytes32 initializable = keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1))
            & ~bytes32(uint256(0xff));
        bytes32[6] memory others = [
            CORPORATE_ACTION_STORAGE_LOCATION,
            CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION,
            ERC20_STORAGE_LOCATION,
            ERC1155_STORAGE_LOCATION,
            UNDERLYING_STORAGE_LOCATION,
            initializable
        ];
        for (uint256 i = 0; i < others.length; i++) {
            assertTrue(ASSET_ID_STORAGE_LOCATION != others[i]);
        }
    }
}
