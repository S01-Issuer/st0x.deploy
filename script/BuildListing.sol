// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {ICloneableFactoryV7} from "rain-factory-0.2.11/src/interface/ICloneableFactoryV7.sol";
import {RegistryBeaconProxyParams} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";

import {TokenConfig} from "../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenParams} from "../src/lib/LibProdTokenParams.sol";
import {
    LibListing,
    LISTING_AUTHORITY,
    LISTING_DOMAIN_NAME,
    LISTING_DOMAIN_SEPARATOR,
    LISTING_DOMAIN_VERSION,
    LISTING_SIGNER_NAME,
    LISTING_TYPEHASH
} from "../src/lib/LibListing.sol";
import {LibListingTree, ListingRow} from "../src/lib/LibListingTree.sol";
import {LibV6Listing} from "../src/lib/LibV6Listing.sol";

/// @title BuildListing
/// @notice Writes `listing.json`: the V6 listing's root, the EIP-712 digest the listing signer signs, and per row its
/// token, fields, leaf, proof and the factory call that deploys the token.
contract BuildListing is Script {
    /// @dev The file this writes.
    string internal constant PATH = "listing.json";

    /// @notice One row's JSON.
    /// @param config The row's token config.
    /// @param rows Every listing row.
    /// @param index The row.
    /// @return The JSON.
    function rowJson(TokenConfig memory config, ListingRow[] memory rows, uint256 index)
        internal
        returns (string memory)
    {
        string memory key = string.concat("rows.", vm.toString(index));
        ListingRow memory row = rows[index];
        RegistryBeaconProxyParams memory params = LibProdTokenParams.tokenParam(config);
        vm.serializeAddress(key, "token", row.token);
        vm.serializeString(key, "assetId", row.assetId);
        vm.serializeString(key, "ticker", row.ticker);
        vm.serializeString(key, "name", row.name);
        vm.serializeBytes32(key, "leaf", LibListing.leaf(row.token, row.assetId, row.ticker, row.name));
        vm.serializeBytes32(key, "proof", LibListingTree.proof(rows, index));
        vm.serializeAddress(key, "deployTo", params.factory);
        return vm.serializeBytes(
            key,
            "deployData",
            abi.encodeCall(
                ICloneableFactoryV7.registryBeaconProxy,
                (params.registry, params.authority, params.beaconName, params.data, params.salt)
            )
        );
    }

    /// @notice `listing.json`.
    /// @return The JSON.
    function render() public returns (string memory) {
        TokenConfig[] memory configs = LibV6Listing.configs();
        ListingRow[] memory rows = LibV6Listing.frozen(configs);
        string[] memory rendered = new string[](rows.length);
        for (uint256 i = 0; i < rows.length; i++) {
            rendered[i] = rowJson(configs[i], rows, i);
        }
        vm.serializeUint("listing", "version", 1);
        vm.serializeString("listing", "domainName", LISTING_DOMAIN_NAME);
        vm.serializeString("listing", "domainVersion", LISTING_DOMAIN_VERSION);
        vm.serializeBytes32("listing", "domainSeparator", LISTING_DOMAIN_SEPARATOR);
        vm.serializeBytes32("listing", "typehash", LISTING_TYPEHASH);
        vm.serializeAddress("listing", "signerAuthority", LISTING_AUTHORITY);
        vm.serializeBytes32("listing", "signerName", LISTING_SIGNER_NAME);
        vm.serializeBytes32("listing", "root", LibV6Listing.ROOT);
        vm.serializeBytes32("listing", "digest", LibListing.digest(LibV6Listing.ROOT));
        return vm.serializeString("listing", "rows", rendered);
    }

    /// @notice Write `listing.json`.
    function run() external {
        vm.writeJson(render(), PATH);
    }
}
