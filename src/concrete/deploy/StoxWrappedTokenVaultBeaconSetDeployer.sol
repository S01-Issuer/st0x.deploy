// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {StoxWrappedTokenVault} from "../StoxWrappedTokenVault.sol";
import {ICLONEABLE_V2_SUCCESS} from "rain.factory/interface/ICloneableV2.sol";

/// @dev Error raised when a zero address is provided for the
/// StoxWrappedTokenVault implementation.
error ZeroVaultImplementation();

/// @dev Error raised when a zero address is provided for the initial beacon
/// owner.
error ZeroBeaconOwner();

/// @dev Error raised when the StoxWrappedTokenVault initialization fails.
error InitializeVaultFailed();

/// @dev Error raised when a zero address is provided for the vault asset.
error ZeroVaultAsset();

struct StoxWrappedTokenVaultBeaconSetDeployerConfig {
    address initialOwner;
    address initialStoxWrappedTokenVaultImplementation;
}

contract StoxWrappedTokenVaultBeaconSetDeployer {
    /// Emitted when a new deployment is successfully initialized.
    /// @param sender The address that initiated the deployment.
    /// @param stoxWrappedTokenVault The address of the deployed
    /// StoxWrappedTokenVault contract.
    event Deployment(address sender, address stoxWrappedTokenVault);

    /// The beacon for the StoxWrappedTokenVault implementation contracts.
    IBeacon public immutable I_STOX_WRAPPED_TOKEN_VAULT_BEACON;

    /// @param config The configuration for the deployer.
    constructor(StoxWrappedTokenVaultBeaconSetDeployerConfig memory config) {
        if (address(config.initialStoxWrappedTokenVaultImplementation) == address(0)) {
            revert ZeroVaultImplementation();
        }
        if (config.initialOwner == address(0)) {
            revert ZeroBeaconOwner();
        }

        I_STOX_WRAPPED_TOKEN_VAULT_BEACON =
            new UpgradeableBeacon(config.initialStoxWrappedTokenVaultImplementation, config.initialOwner);
    }

    /// Deploys and initializes a new StoxWrappedTokenVault contract.
    /// @param asset The address of the underlying asset for the vault.
    /// @return stoxWrappedTokenVault The address of the deployed
    /// StoxWrappedTokenVault contract.
    function newStoxWrappedTokenVault(address asset) external returns (StoxWrappedTokenVault) {
        if (asset == address(0)) {
            revert ZeroVaultAsset();
        }

        StoxWrappedTokenVault stoxWrappedTokenVault =
            StoxWrappedTokenVault(address(new BeaconProxy(address(I_STOX_WRAPPED_TOKEN_VAULT_BEACON), "")));

        if (stoxWrappedTokenVault.initialize(abi.encode(asset)) != ICLONEABLE_V2_SUCCESS) {
            revert InitializeVaultFailed();
        }

        emit Deployment(msg.sender, address(stoxWrappedTokenVault));

        return stoxWrappedTokenVault;
    }
}
