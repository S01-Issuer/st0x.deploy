// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultBeaconSetDeployerConfig
} from "rain-vats-0.1.6/src/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {LibProdDeployCurrent} from "../../generated/LibProdDeployCurrent.sol";

/// @title StoxOffchainAssetReceiptVaultBeaconSetDeployer
/// @notice Inherits OffchainAssetReceiptVaultBeaconSetDeployer with a
/// parameterless constructor that hardcodes the config from LibProdDeployCurrent.
/// This makes the contract Zoltu-deployable.
contract StoxOffchainAssetReceiptVaultBeaconSetDeployer is
    OffchainAssetReceiptVaultBeaconSetDeployer(OffchainAssetReceiptVaultBeaconSetDeployerConfig({
            initialOwner: LibProdDeployCurrent.BEACON_INITIAL_OWNER,
            initialReceiptImplementation: LibProdDeployCurrent.STOX_RECEIPT,
            initialOffchainAssetReceiptVaultImplementation: LibProdDeployCurrent.STOX_RECEIPT_VAULT
        }))
{}
