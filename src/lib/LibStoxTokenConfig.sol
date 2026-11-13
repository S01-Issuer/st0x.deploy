// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Region} from "./LibProdTokenConfig.sol";

bytes32 constant STOX_TOKEN_CONFIG_STORAGE_LOCATION =
    keccak256(abi.encode(uint256(keccak256("rain.storage.stox-token-config.1")) - 1)) & ~bytes32(uint256(0xff));

bytes32 constant INITIALIZABLE_STORAGE_LOCATION =
    keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff));

library LibStoxTokenConfig {
    /// @custom:storage-location erc7201:rain.storage.stox-token-config.1
    /// @dev Append only.
    struct StoxTokenConfigStorage {
        string assetId;
        string listingTicker;
        string listingName;
        Region region;
    }

    function getStorage() internal pure returns (StoxTokenConfigStorage storage s) {
        bytes32 position = STOX_TOKEN_CONFIG_STORAGE_LOCATION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }

    function isUninitialized() internal view returns (bool) {
        bytes32 position = INITIALIZABLE_STORAGE_LOCATION;
        uint256 value;
        assembly ("memory-safe") {
            value := sload(position)
        }
        return value == 0;
    }
}
