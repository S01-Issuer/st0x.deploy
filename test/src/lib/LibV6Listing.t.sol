// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MerkleProof} from "@openzeppelin-contracts-5.7.0/utils/cryptography/MerkleProof.sol";

import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibListing} from "../../../src/lib/LibListing.sol";
import {LibProdTokenParams} from "../../../src/lib/LibProdTokenParams.sol";
import {ICloneableFactoryV7} from "rain-factory-0.2.11/src/interface/ICloneableFactoryV7.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyParams
} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {LibListingTree, ListingRow} from "../../../src/lib/LibListingTree.sol";
import {LibV6Listing, V6ListingMoved, V6ListingTableShort} from "../../../src/lib/LibV6Listing.sol";

/// @title LibV6ListingTest
/// @notice The V6 listing names the leading 59 production V6 rows and the two test tokens under a frozen root; any edit
/// to them is refused, and `listing.json` is that listing.
contract LibV6ListingTest is Test {
    function externalFrozen(TokenConfig[] memory listed) external pure returns (ListingRow[] memory) {
        return LibV6Listing.frozen(listed);
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

    /// A row with another ticker, name or asset id moves the root and is refused.
    function testAnEditedRowIsRefused() external {
        TokenConfig[] memory listed = LibV6Listing.configs();
        listed[7].underlyingName = string.concat(listed[7].underlyingName, " Holdings");
        bytes32 moved = LibListingTree.root(LibListingTree.rows(listed));
        vm.expectRevert(abi.encodeWithSelector(V6ListingMoved.selector, LibV6Listing.ROOT, moved));
        this.externalFrozen(listed);
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
        ListingRow[] memory listed = LibV6Listing.frozen(LibV6Listing.listedFrom(extended));
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
        ListingRow[] memory rows = LibV6Listing.rows();
        TokenConfig[] memory configs = LibV6Listing.configs();
        for (uint256 i = 0; i < rows.length; i++) {
            string memory at = string.concat(".rows[", vm.toString(i), "]");
            assertEq(vm.parseJsonAddress(json, string.concat(at, ".token")), rows[i].token, "token");
            assertEq(vm.parseJsonString(json, string.concat(at, ".assetId")), rows[i].assetId, "asset id");
            assertEq(vm.parseJsonString(json, string.concat(at, ".ticker")), rows[i].ticker, "ticker");
            assertEq(vm.parseJsonString(json, string.concat(at, ".name")), rows[i].name, "name");
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
