// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IStoxUnderlyingV1
/// @notice The ticker and name of the off-chain asset a ST0x receipt vault
/// tokenizes. Tokens that represent the asset (the receipt vault itself and
/// any wrapper around it) build their ERC-20 `symbol()` / `name()` from these
/// values.
interface IStoxUnderlyingV1 {
    /// @notice Emitted when the underlying ticker and name are set.
    /// @param sender The caller that set the values.
    /// @param oldSymbol The ticker before the update. Empty if unset.
    /// @param oldName The name before the update. Empty if unset.
    /// @param newSymbol The ticker after the update.
    /// @param newName The name after the update.
    event UnderlyingSet(address indexed sender, string oldSymbol, string oldName, string newSymbol, string newName);

    /// @notice The underlying ticker, e.g. "NVDA".
    /// @return The ticker, or the empty string if it has never been set.
    function underlyingSymbol() external view returns (string memory);

    /// @notice The underlying asset's name, e.g. "NVIDIA Corporation".
    /// @return The name, or the empty string if it has never been set.
    function underlyingName() external view returns (string memory);

    /// @notice Sets the underlying ticker and name. Callable by the vault
    /// owner only, and callable again later so the values can follow a
    /// renamed listing. Reverts with `EmptyUnderlyingSymbol` /
    /// `EmptyUnderlyingName` on an empty value.
    /// @param newSymbol The underlying ticker, e.g. "NVDA".
    /// @param newName The underlying asset's name, e.g. "NVIDIA Corporation".
    function setUnderlying(string calldata newSymbol, string calldata newName) external;
}
