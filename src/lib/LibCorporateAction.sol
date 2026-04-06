// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @dev ERC-7201 namespaced storage location for corporate actions.
/// keccak256(abi.encode(uint256(keccak256("rain.storage.corporate-action.1")) - 1)) & ~bytes32(uint256(0xff))
bytes32 constant CORPORATE_ACTION_STORAGE_LOCATION = 0xcce8b403dc927e3ec0218603a262b6c4fcc2985ab628bee1e65a6e26753c8300;

/// @dev Permission hash for scheduling a corporate action via the authorizer.
bytes32 constant SCHEDULE_CORPORATE_ACTION = keccak256("SCHEDULE_CORPORATE_ACTION");

/// @dev Permission hash for cancelling a corporate action via the authorizer.
bytes32 constant CANCEL_CORPORATE_ACTION = keccak256("CANCEL_CORPORATE_ACTION");

/// Thrown when the external type hash has no known bitmap mapping.
/// @param typeHash The unrecognised external identifier.
error UnknownActionType(bytes32 typeHash);

/// @title LibCorporateAction
/// @notice Library for corporate action diamond storage. Uses ERC-7201
/// namespaced storage to avoid collisions with existing vault storage slots.
/// PR1 establishes the storage slot, accessor, and skeleton functions.
/// The struct grows as subsequent PRs add the linked list and rebase logic.
library LibCorporateAction {
    /// @custom:storage-location erc7201:rain.storage.corporate-action.1
    struct CorporateActionStorage {
        /// Placeholder to prove storage read/write works via delegatecall.
        /// Replaced by real fields in PR2.
        uint256 _placeholder;
    }

    /// @dev Accessor for corporate action storage at the ERC-7201 slot.
    function getStorage() internal pure returns (CorporateActionStorage storage s) {
        bytes32 position = CORPORATE_ACTION_STORAGE_LOCATION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }

    /// @notice Map an external type identifier to its internal bitmap and
    /// validate parameters. Reverts if the type hash is not recognised.
    /// Subsequent PRs add concrete type mappings.
    /// @param typeHash External identifier, e.g. keccak256("StockSplit").
    /// @param parameters ABI-encoded parameters for the action type.
    /// @return actionType The internal bitmap for this type.
    function resolveActionType(bytes32 typeHash, bytes memory parameters)
        internal
        pure
        returns (uint256 actionType)
    {
        // Concrete types are added by subsequent PRs.
        (actionType, parameters);
        revert UnknownActionType(typeHash);
    }

    /// @notice Skeleton schedule function. Real implementation comes in PR2.
    /// @return actionId Always returns 0 in this placeholder.
    function schedule(uint256, uint64, bytes memory) internal pure returns (uint256 actionId) {
        return 0;
    }

    /// @notice Skeleton cancel function. Real implementation comes in PR2.
    function cancel(uint256) internal pure {}

    /// @notice Count completed actions. Returns 0 in this placeholder — the
    /// real implementation walks the linked list in PR2.
    function countCompleted() internal pure returns (uint256) {
        return 0;
    }
}
