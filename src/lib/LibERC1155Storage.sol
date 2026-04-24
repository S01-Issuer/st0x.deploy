// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev The ERC-7201 namespaced storage root for OpenZeppelin's
/// `ERC1155Upgradeable`, computed in-source from the spec formula rather
/// than hardcoded as a hex literal. Mirrors `LibERC20Storage`.
bytes32 constant ERC1155_STORAGE_LOCATION =
    keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC1155")) - 1)) & ~bytes32(uint256(0xff));

/// @title LibERC1155Storage
/// @notice Direct storage access to OpenZeppelin ERC1155Upgradeable internals,
/// mirroring the role `LibERC20Storage` plays for the share-side rebase.
/// Used by the receipt-side rebase migration to write
/// `_balances[id][account]` without going through `_update` (which would
/// recurse into the migration logic, emit spurious TransferSingle events,
/// and perform the authorizer callback a second time).
///
/// SAFETY: Tightly coupled to OZ v5's ERC1155Upgradeable ERC-7201 storage
/// layout. The struct at the namespaced slot is:
///   slot+0: mapping(uint256 id => mapping(address account => uint256)) _balances
///   slot+1: mapping(address => mapping(address => bool)) _operatorApprovals
///   slot+2: string _uri
/// If OZ changes this layout, this library MUST be updated and
/// `testErc1155SlotConstantMatchesDerivation` in the accompanying test file
/// will fail first. See the "Breaking dependency bumps" section of `CLAUDE.md`.
///
/// The nested-mapping slot derivation is:
///   outer = keccak256(abi.encode(id, ERC1155_STORAGE_LOCATION))
///   entry = keccak256(abi.encode(account, outer))
/// i.e. two hashes where the inner hash has `_balances` base slot (offset 0)
/// as the second word.
library LibERC1155Storage {
    /// @notice Read an account's raw underlying balance for a given receipt
    /// id at OZ's ERC-7201 `_balances` slot. This is whatever value OZ's
    /// `_update` has last written — no semantic overlay is applied here.
    /// @param account The account to read.
    /// @param id The receipt id.
    /// @return result The raw value of `_balances[id][account]`.
    function underlyingBalance(address account, uint256 id) internal view returns (uint256 result) {
        // Inline assembly only accepts literal number constants; bind the
        // derived constant to a local first.
        bytes32 slot = ERC1155_STORAGE_LOCATION;
        assembly ("memory-safe") {
            // outer = keccak256(abi.encode(id, ERC1155_STORAGE_LOCATION))
            mstore(0x00, id)
            mstore(0x20, slot)
            let outer := keccak256(0x00, 0x40)
            // entry = keccak256(abi.encode(account, outer))
            mstore(0x00, account)
            mstore(0x20, outer)
            result := sload(keccak256(0x00, 0x40))
        }
    }

    /// @notice Write an account's balance for a given receipt id directly to
    /// OZ's ERC-7201 `_balances` slot. Bypasses OZ's `_update` entirely —
    /// no `TransferSingle` event, no authorizer callback.
    /// @param account The account to write.
    /// @param id The receipt id.
    /// @param newBalance The new value to write to `_balances[id][account]`.
    function setUnderlyingBalance(address account, uint256 id, uint256 newBalance) internal {
        bytes32 slot = ERC1155_STORAGE_LOCATION;
        assembly ("memory-safe") {
            mstore(0x00, id)
            mstore(0x20, slot)
            let outer := keccak256(0x00, 0x40)
            mstore(0x00, account)
            mstore(0x20, outer)
            sstore(keccak256(0x00, 0x40), newBalance)
        }
    }
}
