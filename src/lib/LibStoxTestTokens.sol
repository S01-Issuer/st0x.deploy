// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
    OffchainAssetReceiptVaultConfigV3
} from "rain-vats-0.2.9/src/interface/IOffchainAssetReceiptVaultV1.sol";

import {Region} from "./LibProdTokenConfig.sol";
import {LibStoxConfig} from "./LibStoxConfig.sol";

/// @notice The addresses of one region's test token.
/// @param token The token: a registry beacon proxy over the bound vault beacon.
/// @param receipt The token's receipt, which the token makes at `initialize`.
/// @param wrapper The token's wrapper: a registry beacon proxy over the bound
/// wrapper beacon.
struct TestTokenAddresses {
    address token;
    address receipt;
    address wrapper;
}

/// @title LibStoxTestTokens
/// @notice One test token per region, built by the V6 clone factory from the
/// root authority's bindings. Each address commits to the factory, the
/// registry, the authority, a binding name and the init data, and not to the
/// chain or the beacon, so the token, its receipt and its wrapper have the
/// same address on every chain.
library LibStoxTestTokens {
    /// @notice The US test token.
    address internal constant US_TOKEN = address(0x6994c5189fAC8a4a1BA9fdd828EA6F15b44D4E7e);
    /// @notice The US test token's receipt.
    address internal constant US_RECEIPT = address(0x696230bd03b57250491D86124893D4b8152bCb72);
    /// @notice The US test token's wrapper.
    address internal constant US_WRAPPER = address(0x241911D3d01488D9592bcA5B432829cc9DBA8cc5);

    /// @notice The EU test token.
    address internal constant EU_TOKEN = address(0x2FE18C37d4aef03E8A9881717B452BfeD4311c5E);
    /// @notice The EU test token's receipt.
    address internal constant EU_RECEIPT = address(0x3C22F53DcbD0edD9ae10c092B62bca3f4C49eC3e);
    /// @notice The EU test token's wrapper.
    address internal constant EU_WRAPPER = address(0xf761A1Da20331329A8d7EE536938fe6C89DCFc18);

    /// @notice A region's test token name and symbol.
    /// @param region The region.
    /// @return The token name.
    /// @return The token symbol.
    function nameAndSymbol(Region region) internal pure returns (string memory, string memory) {
        return region == Region.EU ? ("EU Test ST0x", "tEUTEST") : ("US Test ST0x", "tUSTEST");
    }

    /// @notice The factory init data of a region's test token: the canonical
    /// V3 config, reading the region's RBAC and the receipt beacon under the
    /// root authority.
    /// @param region The region.
    /// @return The init data.
    function vaultData(Region region) internal pure returns (bytes memory) {
        (string memory name, string memory symbol) = nameAndSymbol(region);
        return abi.encode(
            OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
            OffchainAssetReceiptVaultConfigV3({
                name: name,
                symbol: symbol,
                authority: LibStoxConfig.ROOT_AUTHORITY,
                rbacName: LibStoxConfig.rbacName(region),
                receiptBeaconName: LibStoxConfig.RECEIPT_BEACON_NAME,
                metadata: ""
            })
        );
    }

    /// @notice A region's pinned test token addresses.
    /// @param region The region.
    /// @return The token, receipt and wrapper.
    function addresses(Region region) internal pure returns (TestTokenAddresses memory) {
        return region == Region.EU
            ? TestTokenAddresses({token: EU_TOKEN, receipt: EU_RECEIPT, wrapper: EU_WRAPPER})
            : TestTokenAddresses({token: US_TOKEN, receipt: US_RECEIPT, wrapper: US_WRAPPER});
    }
}
