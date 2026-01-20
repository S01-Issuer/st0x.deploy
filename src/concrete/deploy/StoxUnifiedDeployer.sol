// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultConfigV2,
    OffchainAssetReceiptVault
} from "ethgild/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {StoxWrappedTokenVaultBeaconSetDeployer} from "src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";

struct StoxUnifiedDeployerConfig {
    address offchainAssetReceiptVaultBeaconSetDeployer;
    address stoxWrappedTokenVaultBeaconSetDeployer;
}

contract StoxUnifiedDeployer {
    OffchainAssetReceiptVaultBeaconSetDeployer public immutable I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER;
    StoxWrappedTokenVaultBeaconSetDeployer public immutable I_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER;

    constructor(StoxUnifiedDeployerConfig memory config) {
        I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER =
            OffchainAssetReceiptVaultBeaconSetDeployer(config.offchainAssetReceiptVaultBeaconSetDeployer);
        I_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER =
            StoxWrappedTokenVaultBeaconSetDeployer(config.stoxWrappedTokenVaultBeaconSetDeployer);
    }

    function newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config) external {
        OffchainAssetReceiptVault asset =
            I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER.newOffchainAssetReceiptVault(config);
        I_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER.newStoxWrappedTokenVault(address(asset));
    }
}
