// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";

import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultBeaconSetDeployerConfig
} from "ethgild/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {LibProdDeploy} from "src/lib/LibProdDeploy.sol";
import {StoxReceipt} from "src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "src/concrete/StoxReceiptVault.sol";

contract Deploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new OffchainAssetReceiptVaultBeaconSetDeployer(
            OffchainAssetReceiptVaultBeaconSetDeployerConfig({
                initialOwner: LibProdDeploy.BEACON_INIITAL_OWNER,
                initialReceiptImplementation: address(new StoxReceipt()),
                initialOffchainAssetReceiptVaultImplementation: address(new StoxReceiptVault())
            })
        );

        vm.stopBroadcast();
    }
}
