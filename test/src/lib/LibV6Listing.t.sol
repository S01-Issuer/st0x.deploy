// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MerkleProof} from "@openzeppelin-contracts-5.7.0/utils/cryptography/MerkleProof.sol";

import {LibProdTokenConfig, Region, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {
    LibListing,
    LISTING_AUTHORITY,
    LISTING_DOMAIN_NAME,
    LISTING_DOMAIN_SEPARATOR,
    LISTING_DOMAIN_VERSION,
    LISTING_SIGNER_NAME,
    LISTING_TYPEHASH
} from "../../../src/lib/LibListing.sol";
import {LibProdTokenParams} from "../../../src/lib/LibProdTokenParams.sol";
import {ICloneableFactoryV7} from "rain-factory-0.2.11/src/interface/ICloneableFactoryV7.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyParams
} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {LibListingTree, ListingRow} from "../../../src/lib/LibListingTree.sol";
import {
    LibV6Listing,
    V6ListingRowCount,
    V6ListingTableShort,
    V6ListingTokenMoved
} from "../../../src/lib/LibV6Listing.sol";

/// @title LibV6ListingTest
/// @notice The V6 listing names the leading 59 production V6 rows and the two test tokens with the rows the signer
/// signed under a frozen root; a table rename does not move it, a moved token is refused, and `listing.json` is it.
contract LibV6ListingTest is Test {
    function externalRowsFor(TokenConfig[] memory listed) external pure returns (ListingRow[] memory) {
        return LibV6Listing.rowsFor(listed);
    }

    /// The table derives the frozen root, over 59 production rows then the test tokens.
    function testRootIsFrozen() external pure {
        TokenConfig[] memory listed = LibV6Listing.configs();
        assertEq(listed.length, LibV6Listing.ROW_COUNT + 2, "rows");
        TokenConfig[] memory test = LibProdTokenConfig.testTokenConfigs();
        assertEq(listed[LibV6Listing.ROW_COUNT].assetId, test[0].assetId, "first test token");
        assertEq(listed[LibV6Listing.ROW_COUNT + 1].assetId, test[1].assetId, "second test token");
        assertEq(LibListingTree.root(LibV6Listing.rows()), LibV6Listing.ROOT, "root");
    }

    /// The table still derives the token and asset id of every signed row, in the same order.
    function testTheTableDerivesTheSignedTokens() external pure {
        ListingRow[] memory derived = LibListingTree.rows(LibV6Listing.configs());
        ListingRow[] memory signed = LibV6Listing.rows();
        assertEq(derived.length, signed.length, "rows");
        for (uint256 i = 0; i < signed.length; i++) {
            assertEq(derived[i].token, signed[i].token, signed[i].assetId);
            assertEq(derived[i].assetId, signed[i].assetId, signed[i].assetId);
        }
    }

    /// A listed issuer renamed in the table leaves the signed rows and the root as signed.
    function testARenameInTheTableDoesNotMoveTheListing() external pure {
        TokenConfig[] memory listed = LibV6Listing.configs();
        listed[7].underlyingName = string.concat(listed[7].underlyingName, " Holdings");
        listed[7].underlying = string.concat(listed[7].underlying, "X");
        ListingRow[] memory signed = LibV6Listing.rowsFor(listed);
        assertEq(abi.encode(signed), abi.encode(LibV6Listing.rows()), "signed rows");
        assertEq(LibListingTree.root(signed), LibV6Listing.ROOT, "root");
    }

    /// A test-token rename in the table leaves the signed rows as signed too.
    function testATestTokenRenameDoesNotMoveTheListing() external pure {
        TokenConfig[] memory listed = LibV6Listing.configs();
        listed[LibV6Listing.ROW_COUNT].underlyingName = "US Test Renamed";
        assertEq(abi.encode(LibV6Listing.rowsFor(listed)), abi.encode(LibV6Listing.rows()), "signed rows");
    }

    function externalRowsForWithExtraTestRow() external pure returns (ListingRow[] memory) {
        TokenConfig[] memory listed = LibV6Listing.configs();
        TokenConfig[] memory extended = new TokenConfig[](listed.length + 1);
        for (uint256 i = 0; i < listed.length; i++) {
            extended[i] = listed[i];
        }
        extended[listed.length] = listed[listed.length - 1];
        extended[listed.length].assetId = "ST0XTESTXX";
        return LibV6Listing.rowsFor(extended);
    }

    /// A table that lists another number of rows than the signed listing is refused.
    function testAnotherRowCountIsRefused() external {
        vm.expectRevert(
            abi.encodeWithSelector(V6ListingRowCount.selector, LibV6Listing.ROW_COUNT + 2, LibV6Listing.ROW_COUNT + 3)
        );
        this.externalRowsForWithExtraTestRow();
    }

    /// A table row with another asset id moves its token and is refused.
    function testAnotherAssetIdIsRefused() external {
        TokenConfig[] memory listed = LibV6Listing.configs();
        ListingRow memory signed = LibV6Listing.rows()[7];
        listed[7].assetId = "US0000000001";
        address moved = LibListingTree.rows(listed)[7].token;
        vm.expectRevert(abi.encodeWithSelector(V6ListingTokenMoved.selector, signed.assetId, signed.token, moved));
        this.externalRowsFor(listed);
    }

    function externalRowsForMovedAt(uint256 index) external pure returns (ListingRow[] memory) {
        TokenConfig[] memory listed = LibV6Listing.configs();
        listed[index].region = listed[index].region == Region.US ? Region.EU : Region.US;
        return LibV6Listing.rowsFor(listed);
    }

    /// A table row whose token moves is refused in every place, the first and the last included.
    function testAMovedTokenIsRefusedInEveryRow() external {
        ListingRow[] memory signed = LibV6Listing.rows();
        for (uint256 i = 0; i < signed.length; i++) {
            TokenConfig[] memory listed = LibV6Listing.configs();
            listed[i].region = listed[i].region == Region.US ? Region.EU : Region.US;
            address moved = LibListingTree.rows(listed)[i].token;
            vm.expectRevert(
                abi.encodeWithSelector(V6ListingTokenMoved.selector, signed[i].assetId, signed[i].token, moved)
            );
            this.externalRowsForMovedAt(i);
        }
    }

    /// The asset ids of the signed rows whose ticker or name the table has since changed, in table order. Each is
    /// renamed with `setUnderlying` through the timelock after `nameListing` on every chain, and stays here after that.
    function renamedSinceSigning() internal pure returns (string[] memory) {
        return new string[](0);
    }

    /// Every signed row whose ticker or name differs from the table row in its place is recorded in `renamedSinceSigning`.
    function testTableRenamesAreRecorded() external pure {
        ListingRow[] memory signed = LibV6Listing.rows();
        ListingRow[] memory table = LibListingTree.rows(LibV6Listing.configs());
        string[] memory renamed = renamedSinceSigning();
        uint256 found = 0;
        for (uint256 i = 0; i < signed.length; i++) {
            bool differs = keccak256(bytes(signed[i].ticker)) != keccak256(bytes(table[i].ticker))
                || keccak256(bytes(signed[i].name)) != keccak256(bytes(table[i].name));
            if (differs) {
                assertLt(
                    found,
                    renamed.length,
                    string.concat("record in renamedSinceSigning the rename of ", signed[i].assetId)
                );
                assertEq(renamed[found], signed[i].assetId, "renamed rows in table order");
                found++;
            }
        }
        assertEq(found, renamed.length, "a recorded rename the table does not show");
    }

    /// A table row whose token moves, by another region, is refused.
    function testAMovedTokenIsRefused() external {
        TokenConfig[] memory listed = LibV6Listing.configs();
        ListingRow memory signed = LibV6Listing.rows()[7];
        listed[7].region = listed[7].region == Region.US ? Region.EU : Region.US;
        address moved = LibListingTree.rows(listed)[7].token;
        vm.expectRevert(abi.encodeWithSelector(V6ListingTokenMoved.selector, signed.assetId, signed.token, moved));
        this.externalRowsFor(listed);
    }

    /// A row appended after the listed ones does not move the listing.
    function testAnAppendedRowDoesNotMoveTheListing() external pure {
        TokenConfig[] memory production = LibProdTokenConfig.v6TokenConfigs();
        TokenConfig[] memory extended = new TokenConfig[](production.length + 1);
        for (uint256 i = 0; i < production.length; i++) {
            extended[i] = production[i];
        }
        extended[production.length] = TokenConfig({
            underlying: "APPENDED",
            name: "",
            symbol: "tAPPENDED",
            region: production[0].region,
            underlyingName: "Appended Row",
            assetId: "US0000000000"
        });
        ListingRow[] memory listed = LibV6Listing.rowsFor(LibV6Listing.listedFrom(extended));
        assertEq(listed.length, LibV6Listing.ROW_COUNT + 2, "rows");
        assertEq(LibListingTree.root(listed), LibV6Listing.ROOT, "root");
    }

    function externalListedFrom(TokenConfig[] memory production) external pure returns (TokenConfig[] memory) {
        return LibV6Listing.listedFrom(production);
    }

    /// A table with fewer V6 rows than the listing names is refused.
    function testAShortTableIsRefused() external {
        TokenConfig[] memory production = LibProdTokenConfig.v6TokenConfigs();
        TokenConfig[] memory short = new TokenConfig[](LibV6Listing.ROW_COUNT - 1);
        for (uint256 i = 0; i < short.length; i++) {
            short[i] = production[i];
        }
        vm.expectRevert(
            abi.encodeWithSelector(V6ListingTableShort.selector, LibV6Listing.ROW_COUNT, LibV6Listing.ROW_COUNT - 1)
        );
        this.externalListedFrom(short);
    }

    /// Every row's proof verifies against the frozen root.
    function testEveryRowVerifies() external pure {
        ListingRow[] memory rows = LibV6Listing.rows();
        for (uint256 i = 0; i < rows.length; i++) {
            bytes32 leaf = LibListing.leaf(rows[i].token, rows[i].assetId, rows[i].ticker, rows[i].name);
            assertTrue(MerkleProof.verify(LibListingTree.proof(rows, i), LibV6Listing.ROOT, leaf), rows[i].ticker);
        }
    }

    /// `listing.json` holds the frozen root, its digest, and every row's token, fields, proof and the factory call that
    /// deploys that token.
    function testListingJsonIsTheListing() external view {
        string memory json = vm.readFile("listing.json");
        assertEq(vm.parseJsonBytes32(json, ".root"), LibV6Listing.ROOT, "root");
        assertEq(vm.parseJsonBytes32(json, ".digest"), LibListing.digest(LibV6Listing.ROOT), "digest");
        assertEq(vm.parseJsonUint(json, ".version"), 1, "version");
        assertEq(vm.parseJsonString(json, ".domainName"), LISTING_DOMAIN_NAME, "domain name");
        assertEq(vm.parseJsonString(json, ".domainVersion"), LISTING_DOMAIN_VERSION, "domain version");
        assertEq(vm.parseJsonBytes32(json, ".domainSeparator"), LISTING_DOMAIN_SEPARATOR, "domain separator");
        assertEq(vm.parseJsonBytes32(json, ".typehash"), LISTING_TYPEHASH, "typehash");
        assertEq(vm.parseJsonAddress(json, ".signerAuthority"), LISTING_AUTHORITY, "signer authority");
        assertEq(vm.parseJsonBytes32(json, ".signerName"), LISTING_SIGNER_NAME, "signer name");
        ListingRow[] memory rows = LibV6Listing.rows();
        TokenConfig[] memory configs = LibV6Listing.configs();
        for (uint256 i = 0; i < rows.length; i++) {
            string memory at = string.concat(".rows[", vm.toString(i), "]");
            assertEq(vm.parseJsonAddress(json, string.concat(at, ".token")), rows[i].token, "token");
            assertEq(vm.parseJsonString(json, string.concat(at, ".assetId")), rows[i].assetId, "asset id");
            assertEq(vm.parseJsonString(json, string.concat(at, ".ticker")), rows[i].ticker, "ticker");
            assertEq(vm.parseJsonString(json, string.concat(at, ".name")), rows[i].name, "name");
            assertEq(
                vm.parseJsonBytes32(json, string.concat(at, ".leaf")),
                LibListing.leaf(rows[i].token, rows[i].assetId, rows[i].ticker, rows[i].name),
                "leaf"
            );
            RegistryBeaconProxyParams memory params = LibProdTokenParams.tokenParam(configs[i]);
            assertEq(vm.parseJsonAddress(json, string.concat(at, ".deployTo")), params.factory, "deploy to");
            assertEq(
                vm.parseJsonBytes(json, string.concat(at, ".deployData")),
                abi.encodeCall(
                    ICloneableFactoryV7.registryBeaconProxy,
                    (params.registry, params.authority, params.beaconName, params.data, params.salt)
                ),
                "deploy data"
            );
            assertEq(
                LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(params),
                rows[i].token,
                "deployed token"
            );
            bytes32[] memory proof = vm.parseJsonBytes32Array(json, string.concat(at, ".proof"));
            bytes32[] memory expected = LibListingTree.proof(rows, i);
            assertEq(proof.length, expected.length, "proof length");
            for (uint256 j = 0; j < proof.length; j++) {
                assertEq(proof[j], expected[j], "proof");
            }
        }
    }
}
