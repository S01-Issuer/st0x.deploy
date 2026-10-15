// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IAuthorisable
/// @notice Minimal authoriser-getter surface exposed by ST0x receipt vaults.
/// Returns `address` rather than reusing the upstream `IAuthorizableV1` so
/// the token-invariant checks carry a narrow surface and not the upstream's
/// richer return type.
interface IAuthorisable {
    /// @notice The authoriser contract gating restricted vault operations.
    /// @return The authoriser address.
    function authorizer() external view returns (address);
}
