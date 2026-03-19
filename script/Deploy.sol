// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {LibProdDeployV2} from "../src/lib/LibProdDeployV2.sol";
import {StoxReceipt} from "../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer
} from "../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {StoxUnifiedDeployer} from "../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {
    StoxOffchainAssetReceiptVaultBeaconSetDeployer
} from "../src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol";

/// @dev Error thrown when the DEPLOYMENT_SUITE env var does not match any
/// known suite.
error UnknownDeploymentSuite(bytes32 suite);

// One suite per contract to avoid Zoltu factory nonce issues.

bytes32 constant DEPLOYMENT_SUITE_STOX_RECEIPT = keccak256("stox-receipt");
bytes32 constant DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT = keccak256("stox-receipt-vault");
bytes32 constant DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT = keccak256("stox-wrapped-token-vault");
bytes32 constant DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON = keccak256("stox-wrapped-token-vault-beacon");
bytes32 constant DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER =
    keccak256("stox-wrapped-token-vault-beacon-set-deployer");
bytes32 constant DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER =
    keccak256("stox-offchain-asset-receipt-vault-beacon-set-deployer");
bytes32 constant DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER = keccak256("stox-unified-deployer");

contract Deploy is Script {
    mapping(string => mapping(address => bytes32)) internal depCodeHashes;

    function deploySuite(
        bytes memory creationCode,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        address[] memory dependencies
    ) internal {
        string[] memory networks = LibRainDeploy.supportedNetworks();
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");

        console2.log("Suite deploying:", contractPath);
        console2.log("Expected address:", expectedAddress);
        console2.log("Expected codehash:");
        console2.logBytes32(expectedCodeHash);
        console2.log("Chain ID:", block.chainid);
        console2.log("Block number:", block.number);
        console2.log("Dependencies count:", dependencies.length);
        for (uint256 i = 0; i < dependencies.length; i++) {
            console2.log("  Dep address:", dependencies[i]);
            console2.log("  Dep code length:", dependencies[i].code.length);
            console2.log("  Dep codehash:");
            console2.logBytes32(dependencies[i].codehash);
        }

        LibRainDeploy.deployAndBroadcast(
            vm,
            networks,
            deployerPrivateKey,
            creationCode,
            contractPath,
            expectedAddress,
            expectedCodeHash,
            dependencies,
            depCodeHashes
        );
    }

    /// @notice Entry point for the deployment script.
    /// @dev Requires env vars:
    /// - `DEPLOYMENT_KEY`: private key for the deployer account.
    /// - `DEPLOYMENT_SUITE`: which contract to deploy (e.g. "stox-receipt",
    ///   "stox-wrapped-token-vault-beacon", etc.). One contract per run.
    function run() public {
        bytes32 suite = keccak256(bytes(vm.envString("DEPLOYMENT_SUITE")));
        address[] memory noDeps = new address[](0);

        if (suite == DEPLOYMENT_SUITE_STOX_RECEIPT) {
            deploySuite(
                type(StoxReceipt).creationCode,
                "src/concrete/StoxReceipt.sol:StoxReceipt",
                LibProdDeployV2.STOX_RECEIPT,
                LibProdDeployV2.STOX_RECEIPT_CODEHASH,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT) {
            deploySuite(
                type(StoxReceiptVault).creationCode,
                "src/concrete/StoxReceiptVault.sol:StoxReceiptVault",
                LibProdDeployV2.STOX_RECEIPT_VAULT,
                LibProdDeployV2.STOX_RECEIPT_VAULT_CODEHASH,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT) {
            deploySuite(
                type(StoxWrappedTokenVault).creationCode,
                "src/concrete/StoxWrappedTokenVault.sol:StoxWrappedTokenVault",
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT,
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_CODEHASH,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON) {
            address[] memory deps = new address[](1);
            deps[0] = LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT;
            deploySuite(
                type(StoxWrappedTokenVaultBeacon).creationCode,
                "src/concrete/StoxWrappedTokenVaultBeacon.sol:StoxWrappedTokenVaultBeacon",
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON,
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER) {
            address[] memory deps = new address[](1);
            deps[0] = LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON;
            deploySuite(
                type(StoxWrappedTokenVaultBeaconSetDeployer).creationCode,
                "src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol:StoxWrappedTokenVaultBeaconSetDeployer",
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER,
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER) {
            address[] memory deps = new address[](2);
            deps[0] = LibProdDeployV2.STOX_RECEIPT;
            deps[1] = LibProdDeployV2.STOX_RECEIPT_VAULT;
            deploySuite(
                type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode,
                "src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol:StoxOffchainAssetReceiptVaultBeaconSetDeployer",
                LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
                LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER) {
            deploySuite(
                type(StoxUnifiedDeployer).creationCode,
                "src/concrete/deploy/StoxUnifiedDeployer.sol:StoxUnifiedDeployer",
                LibProdDeployV2.STOX_UNIFIED_DEPLOYER,
                LibProdDeployV2.STOX_UNIFIED_DEPLOYER_CODEHASH,
                noDeps
            );
        } else {
            revert UnknownDeploymentSuite(suite);
        }
    }
}
