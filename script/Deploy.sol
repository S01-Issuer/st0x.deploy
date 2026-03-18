// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";

import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {LibProdDeployV2} from "../src/lib/LibProdDeployV2.sol";
import {StoxReceipt} from "../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {StoxWrappedTokenVaultBeaconSetDeployer} from "../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {StoxUnifiedDeployer} from "../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {StoxOffchainAssetReceiptVaultBeaconSetDeployer} from "../src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol";

/// @dev Error thrown when the DEPLOYMENT_SUITE env var does not match any
/// known suite.
error UnknownDeploymentSuite(bytes32 suite);

/// @dev The deployment suite name for the offchain asset receipt vault beacon
/// set.
bytes32 constant DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET =
    keccak256("offchain-asset-receipt-vault-beacon-set");

/// @dev The deployment suite name for the wrapped token vault beacon set.
bytes32 constant DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET = keccak256("wrapped-token-vault-beacon-set");

/// @dev The deployment suite name for the unified deployer.
bytes32 constant DEPLOYMENT_SUITE_UNIFIED_DEPLOYER = keccak256("unified-deployer");

contract Deploy is Script {
    mapping(string => mapping(address => bytes32)) internal depCodeHashes;

    /// @notice Deploys the wrapped token vault beacon set via Zoltu.
    /// Deploys implementation, beacon, and deployer — all deterministic.
    function deployWrappedTokenVaultBeaconSet() internal {
        string[] memory networks = LibRainDeploy.supportedNetworks();
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        address[] memory dependencies = new address[](0);

        LibRainDeploy.deployAndBroadcast(
            vm,
            networks,
            deployerPrivateKey,
            type(StoxWrappedTokenVault).creationCode,
            "src/concrete/StoxWrappedTokenVault.sol:StoxWrappedTokenVault",
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT,
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_CODEHASH,
            dependencies,
            depCodeHashes
        );

        // Beacon depends on the implementation being deployed.
        dependencies = new address[](1);
        dependencies[0] = LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT;

        LibRainDeploy.deployAndBroadcast(
            vm,
            networks,
            deployerPrivateKey,
            type(StoxWrappedTokenVaultBeacon).creationCode,
            "src/concrete/StoxWrappedTokenVaultBeacon.sol:StoxWrappedTokenVaultBeacon",
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON,
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH,
            dependencies,
            depCodeHashes
        );

        // Deployer depends on the beacon being deployed.
        dependencies = new address[](1);
        dependencies[0] = LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON;

        LibRainDeploy.deployAndBroadcast(
            vm,
            networks,
            deployerPrivateKey,
            type(StoxWrappedTokenVaultBeaconSetDeployer).creationCode,
            "src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol:StoxWrappedTokenVaultBeaconSetDeployer",
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER,
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH,
            dependencies,
            depCodeHashes
        );
    }

    /// @notice Deploys the StoxUnifiedDeployer via Zoltu.
    function deployUnifiedDeployer() internal {
        string[] memory networks = LibRainDeploy.supportedNetworks();
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        address[] memory dependencies = new address[](0);

        LibRainDeploy.deployAndBroadcast(
            vm,
            networks,
            deployerPrivateKey,
            type(StoxUnifiedDeployer).creationCode,
            "src/concrete/deploy/StoxUnifiedDeployer.sol:StoxUnifiedDeployer",
            LibProdDeployV2.STOX_UNIFIED_DEPLOYER,
            LibProdDeployV2.STOX_UNIFIED_DEPLOYER_CODEHASH,
            dependencies,
            depCodeHashes
        );
    }

    /// @notice Deploys the offchain asset receipt vault beacon set via Zoltu.
    /// Deploys implementations (StoxReceipt, StoxReceiptVault) then the
    /// beacon set deployer — all deterministic.
    function deployOffchainAssetReceiptVaultBeaconSet() internal {
        string[] memory networks = LibRainDeploy.supportedNetworks();
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        address[] memory dependencies = new address[](0);

        LibRainDeploy.deployAndBroadcast(
            vm,
            networks,
            deployerPrivateKey,
            type(StoxReceipt).creationCode,
            "src/concrete/StoxReceipt.sol:StoxReceipt",
            LibProdDeployV2.STOX_RECEIPT,
            LibProdDeployV2.STOX_RECEIPT_CODEHASH,
            dependencies,
            depCodeHashes
        );

        LibRainDeploy.deployAndBroadcast(
            vm,
            networks,
            deployerPrivateKey,
            type(StoxReceiptVault).creationCode,
            "src/concrete/StoxReceiptVault.sol:StoxReceiptVault",
            LibProdDeployV2.STOX_RECEIPT_VAULT,
            LibProdDeployV2.STOX_RECEIPT_VAULT_CODEHASH,
            dependencies,
            depCodeHashes
        );

        // OARV deployer depends on both implementations.
        dependencies = new address[](2);
        dependencies[0] = LibProdDeployV2.STOX_RECEIPT;
        dependencies[1] = LibProdDeployV2.STOX_RECEIPT_VAULT;

        LibRainDeploy.deployAndBroadcast(
            vm,
            networks,
            deployerPrivateKey,
            type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode,
            "src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol:StoxOffchainAssetReceiptVaultBeaconSetDeployer",
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH,
            dependencies,
            depCodeHashes
        );
    }

    /// @notice Entry point for the deployment script.
    function run() public {
        bytes32 suite = keccak256(bytes(vm.envString("DEPLOYMENT_SUITE")));

        if (suite == DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET) {
            deployOffchainAssetReceiptVaultBeaconSet();
        } else if (suite == DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET) {
            deployWrappedTokenVaultBeaconSet();
        } else if (suite == DEPLOYMENT_SUITE_UNIFIED_DEPLOYER) {
            deployUnifiedDeployer();
        } else {
            revert UnknownDeploymentSuite(suite);
        }
    }
}
