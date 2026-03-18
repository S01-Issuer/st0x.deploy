// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std/Vm.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {LibProdDeployV2} from "../../src/lib/LibProdDeployV2.sol";
import {StoxReceipt} from "../../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer
} from "../../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {StoxUnifiedDeployer} from "../../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {
    StoxOffchainAssetReceiptVaultBeaconSetDeployer
} from "../../src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol";

/// @title LibTestDeploy
/// @notice Deploys the full Stox contract suite via Zoltu in a test
/// environment. Etches the Zoltu factory and deploys each contract,
/// asserting deterministic addresses and codehashes match LibProdDeployV2.
library LibTestDeploy {
    function deployWrappedTokenVaultBeaconSet(Vm vm) internal {
        LibRainDeploy.etchZoltuFactory(vm);

        address vault = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        require(vault == LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT, "StoxWrappedTokenVault address mismatch");

        address beacon = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeacon).creationCode);
        require(
            beacon == LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON, "StoxWrappedTokenVaultBeacon address mismatch"
        );

        address deployer = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeaconSetDeployer).creationCode);
        require(
            deployer == LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER,
            "StoxWrappedTokenVaultBeaconSetDeployer address mismatch"
        );
    }

    function deployOffchainAssetReceiptVaultBeaconSet(Vm vm) internal {
        LibRainDeploy.etchZoltuFactory(vm);

        address receipt = LibRainDeploy.deployZoltu(type(StoxReceipt).creationCode);
        require(receipt == LibProdDeployV2.STOX_RECEIPT, "StoxReceipt address mismatch");

        address receiptVault = LibRainDeploy.deployZoltu(type(StoxReceiptVault).creationCode);
        require(receiptVault == LibProdDeployV2.STOX_RECEIPT_VAULT, "StoxReceiptVault address mismatch");

        address deployer = LibRainDeploy.deployZoltu(type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode);
        require(
            deployer == LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
            "StoxOffchainAssetReceiptVaultBeaconSetDeployer address mismatch"
        );
    }

    function deployAll(Vm vm) internal {
        deployWrappedTokenVaultBeaconSet(vm);
        deployOffchainAssetReceiptVaultBeaconSet(vm);

        address unified = LibRainDeploy.deployZoltu(type(StoxUnifiedDeployer).creationCode);
        require(unified == LibProdDeployV2.STOX_UNIFIED_DEPLOYER, "StoxUnifiedDeployer address mismatch");
    }
}
