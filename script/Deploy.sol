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
import {
    StoxWrappedTokenVaultBeaconSetDeployer,
    StoxWrappedTokenVaultBeaconSetDeployerConfig
} from "src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {StoxWrappedTokenVault} from "src/concrete/StoxWrappedTokenVault.sol";
import {StoxUnifiedDeployer} from "src/concrete/deploy/StoxUnifiedDeployer.sol";

bytes32 constant DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET =
    keccak256("offchain-asset-receipt-vault-beacon-set");

bytes32 constant DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET = keccak256("wrapped-token-vault-beacon-set");

bytes32 constant DEPLOYMENT_SUITE_UNIFIED_DEPLOYER = keccak256("unified-deployer");

contract Deploy is Script {
    function deployOffchainAssetReceiptVaultBeaconSet(uint256 deploymentKey) internal {
        vm.startBroadcast(deploymentKey);

        new OffchainAssetReceiptVaultBeaconSetDeployer(
            OffchainAssetReceiptVaultBeaconSetDeployerConfig({
                initialOwner: LibProdDeploy.BEACON_INIITAL_OWNER,
                initialReceiptImplementation: address(new StoxReceipt()),
                initialOffchainAssetReceiptVaultImplementation: address(new StoxReceiptVault())
            })
        );

        vm.stopBroadcast();
    }

    function deployWrappedTokenVaultBeaconSet(uint256 deploymentKey) internal {
        vm.startBroadcast(deploymentKey);

        new StoxWrappedTokenVaultBeaconSetDeployer(
            StoxWrappedTokenVaultBeaconSetDeployerConfig({
                initialOwner: LibProdDeploy.BEACON_INIITAL_OWNER,
                initialStoxWrappedTokenVaultImplementation: address(new StoxWrappedTokenVault())
            })
        );

        vm.stopBroadcast();
    }

    function deployUnifiedDeployer(uint256 deploymentKey) internal {
        vm.startBroadcast(deploymentKey);

        new StoxUnifiedDeployer();

        vm.stopBroadcast();
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        bytes32 suite = keccak256(bytes(vm.envString("DEPLOYMENT_SUITE")));

        if (suite == DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET) {
            deployOffchainAssetReceiptVaultBeaconSet(deployerPrivateKey);
        } else if (suite == DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET) {
            deployWrappedTokenVaultBeaconSet(deployerPrivateKey);
        } else if (suite == DEPLOYMENT_SUITE_UNIFIED_DEPLOYER) {
            deployUnifiedDeployer(deployerPrivateKey);
        } else {
            revert("Unknown deployment suite");
        }
    }
}
