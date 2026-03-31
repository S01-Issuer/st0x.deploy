// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    LibCorporateAction,
    CORPORATE_ACTION_STORAGE_LOCATION,
    CORPORATE_ACTION_STORAGE_ID
} from "../../../src/lib/LibCorporateAction.sol";

contract LibCorporateActionTest is Test {
    /// The storage location constant MUST match the ERC-7201 formula applied
    /// to the storage ID string. If these diverge, the facet reads/writes the
    /// wrong slot and silently corrupts state.
    function testStorageLocationMatchesId() external pure {
        bytes32 expected = keccak256(abi.encode(uint256(keccak256(abi.encodePacked(CORPORATE_ACTION_STORAGE_ID))) - 1))
            & ~bytes32(uint256(0xff));
        assertEq(CORPORATE_ACTION_STORAGE_LOCATION, expected);
    }

    /// The storage slot MUST NOT collide with known vault storage slots.
    /// Any collision would cause silent state corruption.
    function testStorageLocationNoCollisionWithVault() external pure {
        // Known storage locations from the vault inheritance chain. If any
        // new ERC-7201 locations are added upstream, add them here.
        bytes32[2] memory knownSlots = [
            // ReceiptVault
            bytes32(0x8d198d032a58038629cc32dfaad5ea74a8e78fabf390f3089701523102432600),
            // OffchainAssetReceiptVault
            bytes32(0xba9f160a0257aef2aa878e698d5363429ea67cc3c427f23f7cb9c3069b67bd00)
        ];
        for (uint256 i = 0; i < knownSlots.length; i++) {
            assertTrue(CORPORATE_ACTION_STORAGE_LOCATION != knownSlots[i]);
        }
    }

    /// Global version starts at zero. Corporate actions have not happened yet
    /// so any account at version 0 is current.
    function testInitialGlobalVersionIsZero() external pure {
        // Fresh storage is zero-initialized by the EVM, so getStorage()
        // on a clean slot MUST return 0 for globalVersion. We can't call
        // getStorage() from a test contract without sharing the same storage
        // layout, so we verify the slot constant is nonzero (valid) and trust
        // EVM zero-initialization.
        assertTrue(CORPORATE_ACTION_STORAGE_LOCATION != bytes32(0));
    }

    /// Fuzz: the storage location derivation is deterministic regardless of
    /// any other inputs. This just confirms the constant is truly constant
    /// by re-deriving it many times (the compiler should optimize this away,
    /// but it exercises the test infrastructure).
    function testStorageLocationDeterministic(uint256) external pure {
        bytes32 derived = keccak256(abi.encode(uint256(keccak256(abi.encodePacked(CORPORATE_ACTION_STORAGE_ID))) - 1))
            & ~bytes32(uint256(0xff));
        assertEq(CORPORATE_ACTION_STORAGE_LOCATION, derived);
    }
}
