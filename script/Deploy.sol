// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";

import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultBeaconSetDeployerConfig
} from "ethgild/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {LibProdDeployV1} from "../src/lib/LibProdDeployV1.sol";
import {StoxReceipt} from "../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../src/concrete/StoxReceiptVault.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer,
    StoxWrappedTokenVaultBeaconSetDeployerConfig
} from "../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {StoxWrappedTokenVault} from "../src/concrete/StoxWrappedTokenVault.sol";
import {StoxUnifiedDeployer} from "../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";

/// @dev The deployment suite name for the offchain asset receipt vault beacon
/// set.
bytes32 constant DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET =
    keccak256("offchain-asset-receipt-vault-beacon-set");

/// @dev The deployment suite name for the wrapped token vault beacon set.
bytes32 constant DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET = keccak256("wrapped-token-vault-beacon-set");

/// @dev The deployment suite name for the unified deployer.
bytes32 constant DEPLOYMENT_SUITE_UNIFIED_DEPLOYER = keccak256("unified-deployer");

/// @dev Error thrown when the DEPLOYMENT_SUITE env var does not match any
/// known suite.
error UnknownDeploymentSuite(bytes32 suite);

contract Deploy is Script {
    /// @notice Deploys the OffchainAssetReceiptVaultBeaconSetDeployer contract.
    /// Implementations (StoxReceipt, StoxReceiptVault) are deployed via Zoltu
    /// for deterministic addresses. The beacon set deployer itself uses `new`
    /// because it requires constructor args.
    /// @param deploymentKey The private key used to broadcast the deployment
    /// transactions.
    function deployOffchainAssetReceiptVaultBeaconSet(uint256 deploymentKey) internal {
        vm.startBroadcast(deploymentKey);

        address receipt = LibRainDeploy.deployZoltu(type(StoxReceipt).creationCode);
        address receiptVault = LibRainDeploy.deployZoltu(type(StoxReceiptVault).creationCode);

        new OffchainAssetReceiptVaultBeaconSetDeployer(
            OffchainAssetReceiptVaultBeaconSetDeployerConfig({
                initialOwner: LibProdDeployV1.BEACON_INITIAL_OWNER,
                initialReceiptImplementation: receipt,
                initialOffchainAssetReceiptVaultImplementation: receiptVault
            })
        );

        vm.stopBroadcast();
    }

    /// @notice Deploys the StoxWrappedTokenVaultBeaconSetDeployer contract.
    /// The StoxWrappedTokenVault implementation is deployed via Zoltu for a
    /// deterministic address. The beacon set deployer itself uses `new`
    /// because it requires constructor args.
    /// @param deploymentKey The private key used to broadcast the deployment
    /// transactions.
    function deployWrappedTokenVaultBeaconSet(uint256 deploymentKey) internal {
        vm.startBroadcast(deploymentKey);

        address wrappedVault = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);

        new StoxWrappedTokenVaultBeaconSetDeployer(
            StoxWrappedTokenVaultBeaconSetDeployerConfig({
                initialOwner: LibProdDeployV1.BEACON_INITIAL_OWNER,
                initialStoxWrappedTokenVaultImplementation: wrappedVault
            })
        );

        vm.stopBroadcast();
    }

    /// @notice Deploys the StoxUnifiedDeployer contract via Zoltu for a
    /// deterministic address.
    /// @param deploymentKey The private key used to broadcast the deployment
    /// transactions.
    function deployUnifiedDeployer(uint256 deploymentKey) internal {
        vm.startBroadcast(deploymentKey);

        LibRainDeploy.deployZoltu(type(StoxUnifiedDeployer).creationCode);

        vm.stopBroadcast();
    }

    /// @notice Entry point for the deployment script. Dispatches to the
    /// appropriate deployment function based on the DEPLOYMENT_SUITE environment
    /// variable.
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
            revert UnknownDeploymentSuite(suite);
        }
    }
}
