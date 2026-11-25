// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IStoxUnderlyingV2
/// @notice The ticker, name and ISIN of the off-chain asset a ST0x receipt
/// vault tokenizes.
interface IStoxUnderlyingV2 {
    /// @notice Emitted when the underlying override is set.
    /// @param sender The caller that set the values.
    /// @param oldSymbol `underlyingSymbol()` before the update.
    /// @param oldName `underlyingName()` before the update.
    /// @param oldIsin `underlyingIsin()` before the update.
    /// @param newSymbol The override ticker after the update.
    /// @param newName The override name after the update.
    /// @param newIsin The override ISIN after the update.
    event UnderlyingSet(
        address indexed sender,
        string oldSymbol,
        string oldName,
        string oldIsin,
        string newSymbol,
        string newName,
        string newIsin
    );

    /// @notice The underlying ticker, e.g. "NVDA".
    /// @return The override ticker, else the `StoxTokenConfigV1` listing ticker
    /// the vault was initialized with, else the empty string.
    function underlyingSymbol() external view returns (string memory);

    /// @notice The underlying asset's name, e.g. "NVIDIA Corporation".
    /// @return The override name, else the `StoxTokenConfigV1` listing name the
    /// vault was initialized with, else the empty string.
    function underlyingName() external view returns (string memory);

    /// @notice The underlying asset's current ISIN.
    /// @return The override ISIN, else the `StoxTokenConfigV1` asset id the
    /// vault was initialized with, else the empty string.
    function underlyingIsin() external view returns (string memory);

    /// @notice Sets this token's underlying ticker, name and ISIN override,
    /// stamped with `block.timestamp`. Callable by the vault owner only.
    /// Reverts with `MalformedUnderlyingSymbol`, `MalformedUnderlyingName` or
    /// `MalformedUnderlyingIsin` on a refused value.
    /// @param newSymbol The underlying ticker, e.g. "NVDA".
    /// @param newName The underlying asset's name, e.g. "NVIDIA Corporation".
    /// @param newIsin The underlying asset's current ISIN.
    function setUnderlying(string calldata newSymbol, string calldata newName, string calldata newIsin) external;
}
