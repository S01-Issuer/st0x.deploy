// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultConfigV2,
    OffchainAssetReceiptVault
} from "ethgild/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {StoxWrappedTokenVaultBeaconSetDeployer} from "./StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {LibProdDeployV1} from "../../lib/LibProdDeployV1.sol";
import {StoxWrappedTokenVault} from "../StoxWrappedTokenVault.sol";

/// @title StoxUnifiedDeployer
/// @notice Deploys a new OffchainAssetReceiptVault and a new
/// StoxWrappedTokenVault linked to the OffchainAssetReceiptVault atomically.
/// The beacon sets are hardcoded to simplify and harden deployment of this
/// contract by providing an audit trail in git of any address modifications.
contract StoxUnifiedDeployer {
    /// Emitted when a new OffchainAssetReceiptVault and StoxWrappedTokenVault
    /// are deployed.
    /// @param sender The address that initiated the deployment.
    /// @param asset The address of the deployed OffchainAssetReceiptVault.
    /// @param wrapper The address of the deployed StoxWrappedTokenVault.
    event Deployment(address sender, address asset, address wrapper);

    /// @notice Deploys a new OffchainAssetReceiptVault and a new
    /// StoxWrappedTokenVault linked to the OffchainAssetReceiptVault.
    /// @param config The configuration for the OffchainAssetReceiptVault. The
    /// resulting asset address is used to deploy the StoxWrappedTokenVault.
    // Reentrancy is not exploitable here because this contract is entirely
    // stateless — no storage, no balances. A reentrant call would just create
    // another independent vault pair.
    // slither-disable-next-line reentrancy-events
    function newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config) external {
        OffchainAssetReceiptVault asset = OffchainAssetReceiptVaultBeaconSetDeployer(
                LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
            ).newOffchainAssetReceiptVault(config);
        StoxWrappedTokenVault wrappedTokenVault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));

        emit Deployment(msg.sender, address(asset), address(wrappedTokenVault));
    }
}
