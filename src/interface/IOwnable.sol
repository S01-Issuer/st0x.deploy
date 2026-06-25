// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IOwnable
/// @notice Minimal `Ownable`-like surface used by ST0x receipt vaults.
/// Every production receipt vault exposes `owner()`; the token-invariant
/// checks only need the getter, not the transfer/renounce mutators. This
/// narrow surface avoids depending on a richer token-side interface that
/// could drift.
interface IOwnable {
    /// @notice The current owner of the contract.
    /// @return The owner address.
    function owner() external view returns (address);
}
