// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultBeaconSetDeployerConfig
} from "rain-vats-0.1.6/src/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {LibProdDeployV4} from "../../lib/LibProdDeployV4.sol";

/// @title StoxOffchainAssetReceiptVaultBeaconSetDeployer
/// @notice Inherits OffchainAssetReceiptVaultBeaconSetDeployer with a
/// parameterless constructor that hardcodes the config from LibProdDeployV4.
/// This makes the contract Zoltu-deployable.
contract StoxOffchainAssetReceiptVaultBeaconSetDeployer is
    OffchainAssetReceiptVaultBeaconSetDeployer(OffchainAssetReceiptVaultBeaconSetDeployerConfig({
            initialOwner: LibProdDeployV4.BEACON_INITIAL_OWNER,
            initialReceiptImplementation: LibProdDeployV4.STOX_RECEIPT_RAIN_VATS_0_1_6,
            initialOffchainAssetReceiptVaultImplementation: LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6
        }))
{}
