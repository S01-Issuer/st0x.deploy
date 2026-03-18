// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultBeaconSetDeployerConfig
} from "ethgild/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {LibProdDeploy} from "../../lib/LibProdDeploy.sol";
import {LibProdDeployV2} from "../../lib/LibProdDeployV2.sol";

/// @title StoxOffchainAssetReceiptVaultBeaconSetDeployer
/// @notice Inherits OffchainAssetReceiptVaultBeaconSetDeployer with a
/// parameterless constructor that hardcodes the config from LibProdDeploy
/// and LibProdDeployV2. This makes the contract Zoltu-deployable.
contract StoxOffchainAssetReceiptVaultBeaconSetDeployer is
    OffchainAssetReceiptVaultBeaconSetDeployer(OffchainAssetReceiptVaultBeaconSetDeployerConfig({
            initialOwner: LibProdDeploy.BEACON_INITIAL_OWNER,
            initialReceiptImplementation: LibProdDeployV2.STOX_RECEIPT,
            initialOffchainAssetReceiptVaultImplementation: LibProdDeployV2.STOX_RECEIPT_VAULT
        }))
{}
