// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.2.4/src/lib/LibDecimalFloat.sol";
import {
    ACTION_TYPE_INIT_V1,
    ACTION_TYPE_STOCK_SPLIT_V1,
    ACTION_TYPE_STABLES_DIVIDEND_V1,
    BALANCE_MIGRATION_TYPES_MASK,
    VALID_ACTION_TYPES_MASK
} from "src/interface/ICorporateActionsV1.sol";
import {
    CORPORATE_ACTION_STORAGE_LOCATION,
    INIT_V1_TYPE_HASH,
    STOCK_SPLIT_V1_TYPE_HASH,
    STABLES_DIVIDEND_V1_TYPE_HASH,
    SCHEDULE_CORPORATE_ACTION,
    CANCEL_CORPORATE_ACTION
} from "src/lib/LibCorporateAction.sol";
import {CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION} from "src/lib/LibCorporateActionReceipt.sol";
import {ERC20_STORAGE_LOCATION} from "src/lib/LibERC20Storage.sol";
import {ERC1155_STORAGE_LOCATION} from "src/lib/LibERC1155Storage.sol";
import {NODE_NONE} from "src/lib/LibCorporateActionNode.sol";
import {LibStockSplit} from "src/lib/LibStockSplit.sol";
import {
    SCHEDULE_CORPORATE_ACTION_ADMIN,
    CANCEL_CORPORATE_ACTION_ADMIN
} from "src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";

/// @title LibConstantsStructureTest
/// @notice Structural invariants on every named constant in the stack: action
/// type bits, type hashes, permission hashes, storage locations, codec
/// round-trips and sentinels. Each class enumerates its constants in a
/// hardcoded registry array; a new constant is appended there.
contract LibConstantsStructureTest is Test {
    // -------------------------------------------------------------------------
    // Single-source registries
    // -------------------------------------------------------------------------

    /// The action-type bit registry; every action-type structural test
    /// reads through it.
    function _actionTypeRegistry() private pure returns (uint256[] memory) {
        uint256[] memory types_ = new uint256[](3);
        types_[0] = ACTION_TYPE_INIT_V1;
        types_[1] = ACTION_TYPE_STOCK_SPLIT_V1;
        types_[2] = ACTION_TYPE_STABLES_DIVIDEND_V1;
        return types_;
    }

    /// The type-hash registry; the pairwise-distinctness check reads it.
    function _typeHashRegistry() private pure returns (bytes32[] memory) {
        bytes32[] memory hashes_ = new bytes32[](3);
        hashes_[0] = INIT_V1_TYPE_HASH;
        hashes_[1] = STOCK_SPLIT_V1_TYPE_HASH;
        hashes_[2] = STABLES_DIVIDEND_V1_TYPE_HASH;
        return hashes_;
    }

    // -------------------------------------------------------------------------
    // 1. Bitmap action types
    // -------------------------------------------------------------------------

    /// Every `ACTION_TYPE_*_V<N>` constant is a power of two.
    function testActionTypesArePowerOfTwo() external pure {
        uint256[] memory actionTypes = _actionTypeRegistry();

        for (uint256 i; i < actionTypes.length; i++) {
            uint256 t = actionTypes[i];
            assertGt(t, 0, "action type must be non-zero");
            assertEq(t & (t - 1), 0, "action type must be a power of two");
        }
    }

    /// Every pair of `ACTION_TYPE_*_V<N>` constants occupies a distinct bit.
    function testActionTypesPairwiseDisjoint() external pure {
        uint256[] memory actionTypes = _actionTypeRegistry();

        for (uint256 i; i < actionTypes.length; i++) {
            for (uint256 j = i + 1; j < actionTypes.length; j++) {
                assertEq(actionTypes[i] & actionTypes[j], 0, "action types must occupy disjoint bits");
            }
        }
    }

    /// `VALID_ACTION_TYPES_MASK` is the union of every defined
    /// `ACTION_TYPE_*_V<N>` constant.
    function testValidActionTypesMaskMatchesUnion() external pure {
        uint256 expected = ACTION_TYPE_INIT_V1 | ACTION_TYPE_STOCK_SPLIT_V1 | ACTION_TYPE_STABLES_DIVIDEND_V1;
        assertEq(VALID_ACTION_TYPES_MASK, expected, "VALID_ACTION_TYPES_MASK must be union of all action types");
    }

    /// `BALANCE_MIGRATION_TYPES_MASK` is a subset of
    /// `VALID_ACTION_TYPES_MASK`.
    function testBalanceMigrationMaskSubsetOfValidMask() external pure {
        assertEq(
            BALANCE_MIGRATION_TYPES_MASK & ~VALID_ACTION_TYPES_MASK,
            0,
            "BALANCE_MIGRATION_TYPES_MASK must be subset of VALID_ACTION_TYPES_MASK"
        );
        assertEq(
            BALANCE_MIGRATION_TYPES_MASK,
            ACTION_TYPE_INIT_V1 | ACTION_TYPE_STOCK_SPLIT_V1,
            "BALANCE_MIGRATION_TYPES_MASK must equal INIT | STOCK_SPLIT"
        );
    }

    // -------------------------------------------------------------------------
    // 2. Type hashes
    // -------------------------------------------------------------------------

    /// `*_V<N>_TYPE_HASH` constants follow the namespace convention
    /// `st0x.corporate-actions.<kebab-action-name>.<N>`, with the preimage
    /// built from named components. Every `ACTION_TYPE_*_V<N>` has a
    /// matching `*_V<N>_TYPE_HASH` constant, including INIT (bootstrap-only,
    /// not schedulable) and STABLES_DIVIDEND (codec unimplemented).
    bytes constant TYPE_HASH_NAMESPACE_PREFIX = "st0x.corporate-actions.";
    bytes constant TYPE_HASH_VERSION_SEP = ".";

    function _expectedTypeHash(bytes memory kebab, bytes memory version) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(TYPE_HASH_NAMESPACE_PREFIX, kebab, TYPE_HASH_VERSION_SEP, version));
    }

    function testInitV1TypeHashFollowsNamespaceConvention() external pure {
        assertEq(
            INIT_V1_TYPE_HASH,
            _expectedTypeHash("init", "1"),
            "INIT_V1_TYPE_HASH must follow st0x.corporate-actions.<kebab>.<N> convention"
        );
    }

    function testStockSplitV1TypeHashFollowsNamespaceConvention() external pure {
        assertEq(
            STOCK_SPLIT_V1_TYPE_HASH,
            _expectedTypeHash("stock-split", "1"),
            "STOCK_SPLIT_V1_TYPE_HASH must follow st0x.corporate-actions.<kebab>.<N> convention"
        );
    }

    function testStablesDividendV1TypeHashFollowsNamespaceConvention() external pure {
        assertEq(
            STABLES_DIVIDEND_V1_TYPE_HASH,
            _expectedTypeHash("stables-dividend", "1"),
            "STABLES_DIVIDEND_V1_TYPE_HASH must follow st0x.corporate-actions.<kebab>.<N> convention"
        );
    }

    /// All type-hash constants are pairwise distinct.
    function testTypeHashesPairwiseDistinct() external pure {
        bytes32[] memory hashes = _typeHashRegistry();

        for (uint256 i; i < hashes.length; i++) {
            for (uint256 j = i + 1; j < hashes.length; j++) {
                assertTrue(hashes[i] != hashes[j], "type hashes must not collide");
            }
        }
    }

    // -------------------------------------------------------------------------
    // 3. Permission hashes
    // -------------------------------------------------------------------------

    /// Every permission hash equals `keccak256(<constant-name-as-string>)`.
    function testPermissionHashesMatchConstantNames() external pure {
        assertEq(
            SCHEDULE_CORPORATE_ACTION,
            keccak256("SCHEDULE_CORPORATE_ACTION"),
            "SCHEDULE_CORPORATE_ACTION must hash its own name"
        );
        assertEq(
            CANCEL_CORPORATE_ACTION,
            keccak256("CANCEL_CORPORATE_ACTION"),
            "CANCEL_CORPORATE_ACTION must hash its own name"
        );
        assertEq(
            SCHEDULE_CORPORATE_ACTION_ADMIN,
            keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN"),
            "SCHEDULE_CORPORATE_ACTION_ADMIN must hash its own name"
        );
        assertEq(
            CANCEL_CORPORATE_ACTION_ADMIN,
            keccak256("CANCEL_CORPORATE_ACTION_ADMIN"),
            "CANCEL_CORPORATE_ACTION_ADMIN must hash its own name"
        );
    }

    // -------------------------------------------------------------------------
    // 4. ERC-7201 storage locations
    // -------------------------------------------------------------------------

    /// Every `*_STORAGE_LOCATION` constant equals the ERC-7201 derivation
    /// `keccak256(abi.encode(uint256(keccak256(<namespace>)) - 1)) & ~bytes32(uint256(0xff))`
    /// for its namespace.
    function testCorporateActionStorageLocationMatchesNamespace() external pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("rain.storage.corporate-action.1")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(CORPORATE_ACTION_STORAGE_LOCATION, expected);
    }

    function testCorporateActionReceiptStorageLocationMatchesNamespace() external pure {
        bytes32 expected = keccak256(abi.encode(uint256(keccak256("rain.storage.corporate-action-receipt.1")) - 1))
            & ~bytes32(uint256(0xff));
        assertEq(CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION, expected);
    }

    function testErc20StorageLocationMatchesNamespace() external pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(ERC20_STORAGE_LOCATION, expected);
    }

    function testErc1155StorageLocationMatchesNamespace() external pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC1155")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(ERC1155_STORAGE_LOCATION, expected);
    }

    /// Every storage-location constant occupies a distinct slot.
    function testStorageLocationsPairwiseDistinct() external pure {
        bytes32[4] memory slots = [
            CORPORATE_ACTION_STORAGE_LOCATION,
            CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION,
            ERC20_STORAGE_LOCATION,
            ERC1155_STORAGE_LOCATION
        ];

        for (uint256 i; i < slots.length; i++) {
            for (uint256 j = i + 1; j < slots.length; j++) {
                assertTrue(slots[i] != slots[j], "storage locations must not collide");
            }
        }
    }

    // -------------------------------------------------------------------------
    // 5. Versioned function trios — round-trip pin
    // -------------------------------------------------------------------------

    /// Stock-split V1 codec round-trip: `decode(encode(x)) == x`. The
    /// validator's counterpart lives in
    /// `LibStockSplit.t.sol::testFuzzValidMultiplier`.
    function testStockSplitV1CodecRoundTrip() external pure {
        Float input = LibDecimalFloat.packLossless(2, 0);

        bytes memory encoded = LibStockSplit.encodeParametersV1(input);
        Float decoded = LibStockSplit.decodeParametersV1(encoded);

        assertTrue(Float.unwrap(decoded) == Float.unwrap(input), "round-trip must preserve value");
    }

    // -------------------------------------------------------------------------
    // 6. Misc sentinel constants
    // -------------------------------------------------------------------------

    /// `NODE_NONE` is `type(uint256).max`, the null sentinel that
    /// distinguishes "no node" from "the bootstrap node at index 0".
    function testNodeNoneSentinelValue() external pure {
        assertEq(NODE_NONE, type(uint256).max, "NODE_NONE must be type(uint256).max");
    }
}
