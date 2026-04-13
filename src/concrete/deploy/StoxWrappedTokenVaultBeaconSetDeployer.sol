// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {StoxWrappedTokenVault} from "../StoxWrappedTokenVault.sol";
import {ICLONEABLE_V2_SUCCESS} from "rain.factory/interface/ICloneableV2.sol";
import {LibProdDeployV2} from "../../lib/LibProdDeployV2.sol";
import {IStoxWrappedTokenVaultBeaconSetDeployerV1} from "../../interface/IStoxWrappedTokenVaultBeaconSetDeployerV1.sol";

/// @dev Error raised when the StoxWrappedTokenVault initialization fails.
error InitializeVaultFailed();

/// @dev Error raised when a zero address is provided for the vault asset.
error ZeroVaultAsset();

/// @title StoxWrappedTokenVaultBeaconSetDeployer
/// @notice Deploys new StoxWrappedTokenVault beacon proxy instances.
/// The beacon is deployed separately via Zoltu and referenced by its
/// deterministic address. This makes the deployer itself Zoltu-deployable
/// (no constructor args).
/// In practice, using this directly alongside the
/// OffchainAssetReceiptVaultBeaconSetDeployer is error prone and tedious as it
/// is not atomic, so the StoxUnifiedDeployer contract should be used instead
/// for most use cases.
contract StoxWrappedTokenVaultBeaconSetDeployer is IERC165, IStoxWrappedTokenVaultBeaconSetDeployerV1 {
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IStoxWrappedTokenVaultBeaconSetDeployerV1).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /// Emitted when a new deployment is successfully initialized.
    /// @param sender The address that initiated the deployment.
    /// @param stoxWrappedTokenVault The address of the deployed
    /// StoxWrappedTokenVault contract.
    event Deployment(address sender, address stoxWrappedTokenVault);

    /// Deploys and initializes a new StoxWrappedTokenVault contract.
    /// @dev Reentrancy is not exploitable here because this contract holds no
    /// mutable state between calls. Each invocation creates an independent proxy.
    /// @param asset The address of the underlying asset for the vault.
    /// @return stoxWrappedTokenVault The address of the deployed
    /// StoxWrappedTokenVault contract.
    // slither-disable-next-line reentrancy-events
    function newStoxWrappedTokenVault(address asset) external returns (StoxWrappedTokenVault) {
        if (asset == address(0)) {
            revert ZeroVaultAsset();
        }

        StoxWrappedTokenVault stoxWrappedTokenVault =
            StoxWrappedTokenVault(address(new BeaconProxy(LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON, "")));

        emit Deployment(msg.sender, address(stoxWrappedTokenVault));

        if (stoxWrappedTokenVault.initialize(abi.encode(asset)) != ICLONEABLE_V2_SUCCESS) {
            revert InitializeVaultFailed();
        }

        return stoxWrappedTokenVault;
    }
}
