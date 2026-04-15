// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev The ERC-7201 storage location for OpenZeppelin's ERC1155Upgradeable.
/// keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC1155")) - 1)) & ~bytes32(uint256(0xff))
bytes32 constant ERC1155_STORAGE_LOCATION = 0x88be536d5240c274a3b1d3a1be54482fd9caa294f08c62a7cde569f49a3c4500;

/// @title LibERC1155Storage
/// @notice Direct storage access to OpenZeppelin ERC1155Upgradeable internals,
/// mirroring the role `LibERC20Storage` plays for the share-side rebase.
/// Used by the receipt-side rebase migration (PR #7) to write
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
/// will fail first. See `audit/2026-04-09-01/guidelines-advisor.md` and the
/// "Breaking dependency bumps" section of `CLAUDE.md`.
///
/// The nested-mapping slot derivation is:
///   outer = keccak256(abi.encode(id, ERC1155_STORAGE_LOCATION))
///   entry = keccak256(abi.encode(account, outer))
/// i.e. two hashes where the inner hash has `_balances` base slot (offset 0)
/// as the second word.
library LibERC1155Storage {
    /// @notice Read an account's raw stored balance for a given receipt id
    /// directly from OZ's ERC1155 storage.
    /// @param account The account to read.
    /// @param id The receipt id.
    /// @return result The raw stored balance (pre-rebase).
    function getBalance(address account, uint256 id) internal view returns (uint256 result) {
        assembly ("memory-safe") {
            // outer = keccak256(abi.encode(id, ERC1155_STORAGE_LOCATION))
            mstore(0x00, id)
            mstore(0x20, ERC1155_STORAGE_LOCATION)
            let outer := keccak256(0x00, 0x40)
            // entry = keccak256(abi.encode(account, outer))
            mstore(0x00, account)
            mstore(0x20, outer)
            result := sload(keccak256(0x00, 0x40))
        }
    }

    /// @notice Write an account's balance for a given receipt id directly to
    /// OZ's ERC1155 storage.
    /// @param account The account to write.
    /// @param id The receipt id.
    /// @param newBalance The new balance to set.
    function setBalance(address account, uint256 id, uint256 newBalance) internal {
        assembly ("memory-safe") {
            mstore(0x00, id)
            mstore(0x20, ERC1155_STORAGE_LOCATION)
            let outer := keccak256(0x00, 0x40)
            mstore(0x00, account)
            mstore(0x20, outer)
            sstore(keccak256(0x00, 0x40), newBalance)
        }
    }
}
