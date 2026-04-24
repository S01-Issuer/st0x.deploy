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
    /// @dev Derive the storage slot holding `_balances[account]`, i.e.
    /// `keccak256(account || ERC20_STORAGE_LOCATION)` per Solidity's
    /// mapping slot rule with the base at offset 0 of the namespaced
    /// struct.
    function balanceSlot(address account) private pure returns (bytes32 slot) {
        bytes32 base = ERC20_STORAGE_LOCATION;
        assembly ("memory-safe") {
            mstore(0x00, account)
            mstore(0x20, base)
            slot := keccak256(0x00, 0x40)
        }
    }

    /// @notice Read the account's raw underlying balance at OZ's ERC-7201
    /// `_balances` slot. This is whatever value OZ's `_update` has last
    /// written — no semantic overlay is applied here.
    /// @param account The account to read.
    /// @return result The raw value of `_balances[account]`.
    function underlyingBalance(address account) internal view returns (uint256 result) {
        bytes32 slot = balanceSlot(account);
        assembly ("memory-safe") {
            result := sload(slot)
        }
    }

    /// @notice Write the account's raw underlying balance at OZ's ERC-7201
    /// `_balances` slot. Bypasses OZ's `_update` entirely — no `Transfer`
    /// event, no `_totalSupply` adjustment.
    /// @param account The account to write.
    /// @param newBalance The new value to write to `_balances[account]`.
    function setUnderlyingBalance(address account, uint256 newBalance) internal {
        bytes32 slot = balanceSlot(account);
        assembly ("memory-safe") {
            sstore(slot, newBalance)
        }
    }

    /// @notice Read the raw underlying `_totalSupply` at OZ's ERC-7201 slot.
    /// This is whatever value OZ's `_update` has last written; no semantic
    /// overlay is applied here. Consumers that need a rebase-aware or
    /// otherwise-derived supply figure must compute it themselves.
    /// @return supply The raw value of OZ's `_totalSupply`.
    function underlyingTotalSupply() internal view returns (uint256 supply) {
        bytes32 slot = ERC20_STORAGE_LOCATION;
        assembly ("memory-safe") {
            supply := sload(add(slot, 2))
        }
    }
}
