// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {AssetId, Region} from "../interface/IStoxTokenConfigV1.sol";

bytes32 constant STOX_TOKEN_CONFIG_STORAGE_LOCATION =
    keccak256(abi.encode(uint256(keccak256("rain.storage.stox-token-config.1")) - 1)) & ~bytes32(uint256(0xff));

/// @title LibStoxTokenConfig
/// @notice The listing facts a vault was initialized with, read by later
/// implementations.
library LibStoxTokenConfig {
    /// @custom:storage-location erc7201:rain.storage.stox-token-config.1
    /// @dev Append only: live vaults hold this layout.
    struct StoxTokenConfigStorage {
        AssetId assetId;
        string listingTicker;
        string listingName;
        Region region;
    }

    function getStorage() internal pure returns (StoxTokenConfigStorage storage) {
        bytes32 position = STOX_TOKEN_CONFIG_STORAGE_LOCATION;
        StoxTokenConfigStorage storage tokenConfigStorage;
        assembly ("memory-safe") {
            tokenConfigStorage.slot := position
        }
        return tokenConfigStorage;
    }
}
