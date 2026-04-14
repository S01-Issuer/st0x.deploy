// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {StoxWrappedTokenVault} from "../concrete/StoxWrappedTokenVault.sol";

/// @title IStoxWrappedTokenVaultBeaconSetDeployerV1
/// @notice V1 interface for the StoxWrappedTokenVaultBeaconSetDeployer.
interface IStoxWrappedTokenVaultBeaconSetDeployerV1 {
    /// @notice Deploys and initializes a new StoxWrappedTokenVault contract.
    /// @param asset The address of the underlying asset for the vault.
    /// @return stoxWrappedTokenVault The address of the deployed
    /// StoxWrappedTokenVault contract.
    function newStoxWrappedTokenVault(address asset) external returns (StoxWrappedTokenVault stoxWrappedTokenVault);
}
