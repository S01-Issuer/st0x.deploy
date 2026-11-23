// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    LibAssetId,
    ASSET_ID_INITIALIZED,
    ASSET_ID_STORAGE_LOCATION,
    STOX_ASSET_ID_METADATA_V1_TAG
} from "../../../src/lib/LibAssetId.sol";
import {LibAssetIdHarness} from "../../concrete/LibAssetIdHarness.sol";
import {EmptyAssetId, NonCanonicalAssetIdMetadata, UnknownAssetIdMetadata} from "../../../src/error/ErrAssetId.sol";

contract LibAssetIdTest is Test {
    LibAssetIdHarness internal harness = new LibAssetIdHarness();

    /// The ERC-7201 slot for `rain.storage.asset-id.1`, a sibling of the other `rain.storage.<x>.1` namespaces.
    function testStorageLocationIsTheErc7201SlotOfItsNamespace() external pure {
        assertEq(
            ASSET_ID_STORAGE_LOCATION,
            keccak256(abi.encode(uint256(keccak256("rain.storage.asset-id.1")) - 1)) & ~bytes32(uint256(0xff))
        );
        bytes32 slot;
        LibAssetId.AssetIdStorage storage s = LibAssetId.getStorage();
        assembly ("memory-safe") {
            slot := s.slot
        }
        assertEq(slot, ASSET_ID_STORAGE_LOCATION);
    }

    function testMetadataIsTheTaggedAbiEncoding(string memory assetId) external pure {
        assertEq(LibAssetId.encodeMetadata(assetId), abi.encode(STOX_ASSET_ID_METADATA_V1_TAG, assetId));
        assertEq(STOX_ASSET_ID_METADATA_V1_TAG, keccak256("st0x.metadata.asset-id.1"));
        assertEq(ASSET_ID_INITIALIZED, keccak256("st0x.asset-id.initialized.1"));
    }

    function testDecodeRoundTripsEveryNonEmptyAssetId(string memory assetId) external view {
        vm.assume(bytes(assetId).length > 0);
        assertEq(harness.decodeMetadata(LibAssetId.encodeMetadata(assetId)), assetId);
    }

    function testDecodeRejectsAnEmptyAssetId() external {
        vm.expectRevert(EmptyAssetId.selector);
        harness.decodeMetadata(LibAssetId.encodeMetadata(""));
    }

    function testDecodeRejectsMetadataShorterThanATag(bytes memory metadata) external {
        vm.assume(metadata.length < 0x20);
        vm.expectRevert(abi.encodeWithSelector(UnknownAssetIdMetadata.selector, bytes32(0)));
        harness.decodeMetadata(metadata);
    }

    function testDecodeRejectsAnUnknownTag(bytes32 tag, string memory assetId) external {
        vm.assume(tag != STOX_ASSET_ID_METADATA_V1_TAG);
        vm.expectRevert(abi.encodeWithSelector(UnknownAssetIdMetadata.selector, tag));
        harness.decodeMetadata(abi.encode(tag, assetId));
    }

    function testDecodeRejectsTrailingBytes(string memory assetId, bytes memory trailing) external {
        vm.assume(trailing.length > 0);
        vm.expectRevert(NonCanonicalAssetIdMetadata.selector);
        harness.decodeMetadata(bytes.concat(LibAssetId.encodeMetadata(assetId), trailing));
    }

    /// A tag alone has no string offset, so `abi.decode` reverts without data.
    function testDecodeRejectsATagWithNoString() external {
        vm.expectRevert(bytes(""));
        harness.decodeMetadata(abi.encode(STOX_ASSET_ID_METADATA_V1_TAG));
    }
}
