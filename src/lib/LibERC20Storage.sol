// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @dev The ERC-7201 storage location for OpenZeppelin's ERC20Upgradeable.
/// keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff))
bytes32 constant ERC20_STORAGE_LOCATION = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;

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
        assembly ("memory-safe") {
            // _balances is at slot+0 in the struct, so the mapping base slot
            // is ERC20_STORAGE_LOCATION itself.
            mstore(0x00, account)
            mstore(0x20, ERC20_STORAGE_LOCATION)
            result := sload(keccak256(0x00, 0x40))
        }
    }

    /// @notice Write an account's balance directly to storage.
    /// @param account The account to write.
    /// @param newBalance The new balance to set.
    function setBalance(address account, uint256 newBalance) internal {
        assembly ("memory-safe") {
            mstore(0x00, account)
            mstore(0x20, ERC20_STORAGE_LOCATION)
            sstore(keccak256(0x00, 0x40), newBalance)
        }
    }

    /// @notice Read totalSupply directly from storage.
    /// @return supply The raw stored totalSupply.
    function getTotalSupply() internal view returns (uint256 supply) {
        assembly ("memory-safe") {
            // _totalSupply is at slot+2 in the struct.
            supply := sload(add(ERC20_STORAGE_LOCATION, 2))
        }
    }

    /// @notice Write totalSupply directly to storage.
    /// @param supply The new totalSupply to set.
    function setTotalSupply(uint256 supply) internal {
        assembly ("memory-safe") {
            sstore(add(ERC20_STORAGE_LOCATION, 2), supply)
        }
    }
}
