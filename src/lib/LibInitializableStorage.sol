// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @dev OZ 5.x `Initializable`'s private `INITIALIZABLE_STORAGE`, the slot
/// `StoxReceiptVault._initializableStorageSlot()` returns.
bytes32 constant INITIALIZABLE_STORAGE_LOCATION =
    keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff));

/// @title LibInitializableStorage
/// @notice Reads OZ `Initializable` state from code that is not an
/// `Initializable`, such as a facet delegatecalled by the vault.
///
/// SAFETY: coupled to OZ 5.x's `InitializableStorage`, which packs
/// `uint64 _initialized` and `bool _initializing` into its first slot.
library LibInitializableStorage {
    /// @return Whether the vault is initialized, initializing, or has
    /// initializers disabled.
    function isInitialized() internal view returns (bool) {
        bytes32 position = INITIALIZABLE_STORAGE_LOCATION;
        uint256 value;
        assembly ("memory-safe") {
            value := sload(position)
        }
        return value != 0;
    }
}
