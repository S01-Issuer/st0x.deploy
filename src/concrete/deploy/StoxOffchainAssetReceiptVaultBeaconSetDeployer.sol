// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultBeaconSetDeployerConfig
} from "rain.vats/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {LibProdDeployV3} from "../../lib/LibProdDeployV3.sol";

/// @title StoxOffchainAssetReceiptVaultBeaconSetDeployer
/// @notice Inherits OffchainAssetReceiptVaultBeaconSetDeployer with a
/// parameterless constructor that hardcodes the config from LibProdDeployV3.
/// This makes the contract Zoltu-deployable.
contract StoxOffchainAssetReceiptVaultBeaconSetDeployer is
    OffchainAssetReceiptVaultBeaconSetDeployer(OffchainAssetReceiptVaultBeaconSetDeployerConfig({
            initialOwner: LibProdDeployV3.BEACON_INITIAL_OWNER,
            initialReceiptImplementation: LibProdDeployV3.STOX_RECEIPT,
            initialOffchainAssetReceiptVaultImplementation: LibProdDeployV3.STOX_RECEIPT_VAULT
        }))
{}
