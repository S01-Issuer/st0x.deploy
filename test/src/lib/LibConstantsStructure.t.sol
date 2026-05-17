// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
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
/// @notice Cross-cutting structural invariants on every named constant in the
/// stack. The point: adding a new action type, permission, or storage
/// namespace is a multi-file change that's easy to get subtly wrong (rename
/// a constant but not its hash preimage, reuse a bitmap bit already taken,
/// etc). The piecemeal ad-hoc tests catch some of this; this file owns the
/// whole class invariant per shape, so a mis-shaped addition fails one
/// canonical test rather than reviewer vigilance.
///
/// Registry approach: every class enumerates its constants explicitly in a
/// hardcoded array. The bookkeeping cost is a feature — adding a new
/// constant is a deliberate edit to this file with the structural check
/// running on it.
contract LibConstantsStructureTest is Test {
    // -------------------------------------------------------------------------
    // Single-source registries
    // -------------------------------------------------------------------------

    /// Single source of truth for the action-type bit registry. Adding a
    /// new `ACTION_TYPE_*_V<N>` to the codebase means appending it here
    /// once; every action-type structural test reads through this helper
    /// so the new type is automatically covered by the power-of-two and
    /// pairwise-disjoint checks.
    function _actionTypeRegistry() private pure returns (uint256[] memory) {
        uint256[] memory types_ = new uint256[](3);
        types_[0] = ACTION_TYPE_INIT_V1;
        types_[1] = ACTION_TYPE_STOCK_SPLIT_V1;
        types_[2] = ACTION_TYPE_STABLES_DIVIDEND_V1;
        return types_;
    }

    /// Single source of truth for the type-hash registry. Adding a new
    /// `*_V<N>_TYPE_HASH` means appending it here once; the
    /// pairwise-distinctness check picks up the new entry automatically.
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

    /// Every `ACTION_TYPE_*_V<N>` constant must be a power of two so the
    /// bitmap encoding stays unambiguous: `actionType & MASK != 0` matches
    /// when (and only when) the action type is in the mask.
    function testActionTypesArePowerOfTwo() external pure {
        uint256[] memory actionTypes = _actionTypeRegistry();

        for (uint256 i; i < actionTypes.length; i++) {
            uint256 t = actionTypes[i];
            assertGt(t, 0, "action type must be non-zero");
            assertEq(t & (t - 1), 0, "action type must be a power of two");
        }
    }

    /// Every pair of `ACTION_TYPE_*_V<N>` constants occupies a distinct bit.
    /// A collision would make traversal masks ambiguous: a mask intended to
    /// match one type would match the other.
    function testActionTypesPairwiseDisjoint() external pure {
        uint256[] memory actionTypes = _actionTypeRegistry();

        for (uint256 i; i < actionTypes.length; i++) {
            for (uint256 j = i + 1; j < actionTypes.length; j++) {
                assertEq(actionTypes[i] & actionTypes[j], 0, "action types must occupy disjoint bits");
            }
        }
    }

    /// `VALID_ACTION_TYPES_MASK` must be the union of every defined
    /// `ACTION_TYPE_*_V<N>` constant — adding a new type without updating
    /// the union would leave the new type unreachable through the
    /// `mask & VALID_ACTION_TYPES_MASK == 0 → revert` guard in the
    /// traversal getters.
    function testValidActionTypesMaskMatchesUnion() external pure {
        uint256 expected = ACTION_TYPE_INIT_V1 | ACTION_TYPE_STOCK_SPLIT_V1 | ACTION_TYPE_STABLES_DIVIDEND_V1;
        assertEq(VALID_ACTION_TYPES_MASK, expected, "VALID_ACTION_TYPES_MASK must be union of all action types");
    }

    /// `BALANCE_MIGRATION_TYPES_MASK` must be a subset of
    /// `VALID_ACTION_TYPES_MASK`. The migration mask names types that
    /// participate in lazy balance migration; anything outside the valid
    /// set isn't a real action type and would trip the InvalidMask guard.
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

    /// `*_V<N>_TYPE_HASH` constants must follow the namespace convention
    /// `st0x.corporate-actions.<kebab-action-name>.<N>`. Constructing the
    /// preimage from named components rather than hardcoding the literal
    /// string is the structural invariant — a bare `keccak256("…literal…")`
    /// check is just a tautology of the source declaration. With the
    /// component decomposition, drift in the prefix or the version-suffix
    /// dot separator trips every type-hash test at once, while the
    /// bare-string check would only trip on a typo within the hardcoded
    /// literal.
    ///
    /// **One type hash per action type.** Every `ACTION_TYPE_*_V<N>` has a
    /// matching `*_V<N>_TYPE_HASH` constant. Whether `resolveActionType`
    /// dispatches the hash is a separate concern from the structural
    /// invariant — INIT exists as a hash even though it's bootstrap-only
    /// and can't be scheduled, and STABLES_DIVIDEND exists as a hash even
    /// though the codec is unimplemented (the hash pins the convention so
    /// the eventual implementer in #104 has a fixed target). The point of
    /// this file is to catch convention drift at the namespace level —
    /// keeping the (action type, type hash, kebab name) registry uniform
    /// for every action type ensures a future addition can't quietly skip
    /// the structural check.
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

    /// All type-hash constants must be pairwise distinct — a collision
    /// would make dispatch ambiguous in `resolveActionType` (today only
    /// STOCK_SPLIT dispatches, but the invariant must hold for every type
    /// the dispatch may eventually accept).
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

    /// Every permission hash must equal `keccak256(<constant-name-as-string>)`.
    /// This is the established convention across the authorizer surface;
    /// it makes the on-chain identity of a permission unambiguous from its
    /// source-level name.
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

    /// Every `*_STORAGE_LOCATION` constant must equal the ERC-7201
    /// derivation `keccak256(abi.encode(uint256(keccak256(<namespace>)) - 1)) & ~bytes32(uint256(0xff))`
    /// for its documented namespace. Drift between constant and namespace
    /// silently remaps live storage on upgrade — catastrophic and invisible
    /// to bytecode comparison.
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

    /// Every storage-location constant must occupy a distinct slot. A
    /// collision would have two libraries sharing storage at the same
    /// ERC-7201 slot, breaking diamond-storage isolation.
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

    /// Stock-split V1 codec round-trip: `decode(encode(x)) == x`.
    /// Adding a `_V2` validator without the matching encoder/decoder is
    /// caught at compile time (any reference to `encodeParametersV2` /
    /// `decodeParametersV2` fails to resolve until all three exist
    /// together). The validator's behavioural-invariant counterpart
    /// (validate accepts every round-trippable in-range value) lives in
    /// `LibStockSplit.t.sol::testFuzzValidMultiplier`, which has the
    /// per-token-decimals harness this test would otherwise need.
    function testStockSplitV1CodecRoundTrip() external pure {
        Float input = LibDecimalFloat.packLossless(2, 0);

        bytes memory encoded = LibStockSplit.encodeParametersV1(input);
        Float decoded = LibStockSplit.decodeParametersV1(encoded);

        assertTrue(Float.unwrap(decoded) == Float.unwrap(input), "round-trip must preserve value");
    }

    // -------------------------------------------------------------------------
    // 6. Misc sentinel constants
    // -------------------------------------------------------------------------

    /// `NODE_NONE` is `type(uint256).max` — the value-level null sentinel
    /// that distinguishes "no node" from "the bootstrap node at index 0".
    /// Any change here cascades through every `prev`/`next` comparison in
    /// the linked-list traversal. Pinning the literal value prevents an
    /// accidental redefinition (e.g. to 0) from silently re-introducing
    /// the positional disambiguation that issue #79 fixed.
    function testNodeNoneSentinelValue() external pure {
        assertEq(NODE_NONE, type(uint256).max, "NODE_NONE must be type(uint256).max");
    }
}
