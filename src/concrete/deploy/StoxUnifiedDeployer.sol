// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultConfigV2,
    OffchainAssetReceiptVault
} from "rain-vats-0.2.1/src/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {ERC165} from "@openzeppelin-contracts-5.6.1/utils/introspection/ERC165.sol";
import {StoxWrappedTokenVaultBeaconSetDeployer} from "./StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {LibProdDeployCurrent} from "../../generated/LibProdDeployCurrent.sol";
import {StoxWrappedTokenVault} from "../StoxWrappedTokenVault.sol";
import {IStoxUnifiedDeployerV1} from "../../interface/IStoxUnifiedDeployerV1.sol";

/// @title StoxUnifiedDeployer
/// @notice Deploys a new OffchainAssetReceiptVault and a new
/// StoxWrappedTokenVault linked to the OffchainAssetReceiptVault atomically.
/// The beacon set deployer addresses are hardcoded from `LibProdDeployCurrent`.
contract StoxUnifiedDeployer is ERC165, IStoxUnifiedDeployerV1 {
    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IStoxUnifiedDeployerV1).interfaceId || super.supportsInterface(interfaceId);
    }

    /// Emitted when a new OffchainAssetReceiptVault and StoxWrappedTokenVault
    /// are deployed.
    /// @param sender The address that initiated the deployment.
    /// @param asset The address of the deployed OffchainAssetReceiptVault.
    /// @param wrapper The address of the deployed StoxWrappedTokenVault.
    event Deployment(address sender, address asset, address wrapper);

    /// @notice Deploys a new OffchainAssetReceiptVault and a new
    /// StoxWrappedTokenVault linked to the OffchainAssetReceiptVault.
    /// @dev This contract has no storage; a reentrant call creates another
    /// independent vault pair.
    /// @param config The configuration for the OffchainAssetReceiptVault. The
    /// resulting asset address is used to deploy the StoxWrappedTokenVault.
    // slither-disable-next-line reentrancy-events
    function newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config) external {
        OffchainAssetReceiptVault asset = OffchainAssetReceiptVaultBeaconSetDeployer(
                LibProdDeployCurrent.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
            ).newOffchainAssetReceiptVault(config);
        StoxWrappedTokenVault wrappedTokenVault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));

        emit Deployment(msg.sender, address(asset), address(wrappedTokenVault));
    }
}
