// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {OffchainAssetReceiptVaultConfigV2} from "rain.vats/concrete/vault/OffchainAssetReceiptVault.sol";

/// @title IStoxUnifiedDeployerV1
/// @notice V1 interface for the StoxUnifiedDeployer.
interface IStoxUnifiedDeployerV1 {
    /// @notice Deploys a new OffchainAssetReceiptVault and a new
    /// StoxWrappedTokenVault linked to the OffchainAssetReceiptVault.
    /// @param config The configuration for the OffchainAssetReceiptVault.
    function newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config) external;
}
