// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultConfigV2,
    OffchainAssetReceiptVault
} from "ethgild/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {StoxWrappedTokenVaultBeaconSetDeployer} from "src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {LibProdDeploy} from "../../lib/LibProdDeploy.sol";

contract StoxUnifiedDeployer {
    function newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config) external {
        OffchainAssetReceiptVault asset = OffchainAssetReceiptVaultBeaconSetDeployer(
            LibProdDeploy.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
        ).newOffchainAssetReceiptVault(config);
        StoxWrappedTokenVaultBeaconSetDeployer(LibProdDeploy.WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER)
            .newStoxWrappedTokenVault(address(asset));
    }
}
