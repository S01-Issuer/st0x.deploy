// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultBeaconSetDeployerConfig
} from "rain-vats-0.2.7/src/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {LibProdDeployCurrent} from "../../generated/LibProdDeployCurrent.sol";
import {LibStoxConfig} from "../../lib/LibStoxConfig.sol";

/// @title StoxOffchainAssetReceiptVaultBeaconSetDeployer
/// @notice Inherits OffchainAssetReceiptVaultBeaconSetDeployer with a
/// parameterless constructor that hardcodes the implementations from
/// LibProdDeployCurrent and reads the beacons' initial owner from
/// `LibStoxConfig.beaconOwner()`. This makes the contract Zoltu-deployable.
contract StoxOffchainAssetReceiptVaultBeaconSetDeployer is
    OffchainAssetReceiptVaultBeaconSetDeployer(OffchainAssetReceiptVaultBeaconSetDeployerConfig({
            initialOwner: LibStoxConfig.beaconOwner(),
            initialReceiptImplementation: LibProdDeployCurrent.STOX_RECEIPT,
            initialOffchainAssetReceiptVaultImplementation: LibProdDeployCurrent.STOX_RECEIPT_VAULT
        }))
{}
