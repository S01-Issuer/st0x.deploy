// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @dev String ID for the corporate action storage location.
string constant CORPORATE_ACTION_STORAGE_ID = "rain.storage.corporate-action.1";

/// @dev "rain.storage.corporate-action.1" with the erc7201 formula.
/// keccak256(abi.encode(uint256(keccak256("rain.storage.corporate-action.1")) - 1)) & ~bytes32(uint256(0xff))
bytes32 constant CORPORATE_ACTION_STORAGE_LOCATION = 0xcce8b403dc927e3ec0218603a262b6c4fcc2985ab628bee1e65a6e26753c8300;

/// @title LibCorporateAction
/// @notice Library for corporate action diamond storage. Uses ERC-7201
/// namespaced storage to avoid collisions with existing vault storage slots.
/// This is the foundational storage layer that all corporate action
/// functionality builds on.
library LibCorporateAction {
    /// The global version counter. Incremented each time a corporate action
    /// that affects balances is executed. Accounts compare their own version
    /// against this to determine whether migration is needed.
    /// @custom:storage-location erc7201:rain.storage.corporate-action.1
    struct CorporateActionStorage {
        uint256 globalVersion;
    }

    /// @dev Accessor for corporate action storage at the ERC-7201 slot.
    function getStorage() internal pure returns (CorporateActionStorage storage s) {
        bytes32 position = CORPORATE_ACTION_STORAGE_LOCATION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }
}
