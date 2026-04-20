// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev The ERC-7201 namespaced storage root for OpenZeppelin's
/// `ERC20Upgradeable`, computed in-source from the spec formula rather than
/// hardcoded as a hex literal. The compiler evaluates this at deploy time,
/// so there is no runtime cost versus a hardcoded hex.
bytes32 constant ERC20_STORAGE_LOCATION =
    keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff));

/// @title LibERC20Storage
/// @notice Direct storage access to OpenZeppelin ERC20Upgradeable internals.
/// Used by the rebase migration system to write balances and totalSupply
/// without going through `_update`, which would emit spurious Transfer events
/// and create reentrancy concerns.
///
/// SAFETY: This is tightly coupled to OZ v5's ERC20Upgradeable ERC-7201
/// storage layout. The struct layout at the namespaced slot is:
///   slot+0: mapping(address => uint256) _balances
///   slot+1: mapping(address => mapping(address => uint256)) _allowances
///   slot+2: uint256 _totalSupply
/// If OZ changes this layout, this library MUST be updated.
library LibERC20Storage {
    /// @notice Read an account's raw stored balance directly from storage.
    /// @param account The account to read.
    /// @return result The raw stored balance (pre-rebase).
    function getBalance(address account) internal view returns (uint256 result) {
        // Inline assembly only accepts literal number constants; bind the
        // derived constant to a local first.
        bytes32 slot = ERC20_STORAGE_LOCATION;
        assembly ("memory-safe") {
            mstore(0x00, account)
            mstore(0x20, slot)
            result := sload(keccak256(0x00, 0x40))
        }
    }

    /// @notice Write an account's balance directly to storage.
    /// @param account The account to write.
    /// @param newBalance The new balance to set.
    function setBalance(address account, uint256 newBalance) internal {
        bytes32 slot = ERC20_STORAGE_LOCATION;
        assembly ("memory-safe") {
            mstore(0x00, account)
            mstore(0x20, slot)
            sstore(keccak256(0x00, 0x40), newBalance)
        }
    }

    /// @notice Read totalSupply directly from storage.
    /// @return supply The raw stored totalSupply.
    function getTotalSupply() internal view returns (uint256 supply) {
        bytes32 slot = ERC20_STORAGE_LOCATION;
        assembly ("memory-safe") {
            supply := sload(add(slot, 2))
        }
    }
}
