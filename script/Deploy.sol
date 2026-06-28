// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script, console2} from "forge-std-1.16.1/src/Script.sol";

import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";
import {LibProdDeployV2} from "../src/lib/LibProdDeployV2.sol";
import {LibProdDeployV4} from "../src/lib/LibProdDeployV4.sol";
import {LibProdDeployV4} from "../src/lib/LibProdDeployV4.sol";
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
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1
} from "../src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {StoxCorporateActionsFacet} from "../src/concrete/StoxCorporateActionsFacet.sol";

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
bytes32 constant DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1 =
    keccak256("stox-offchain-asset-receipt-vault-authorizer-v1");
bytes32 constant DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1 =
    keccak256("stox-offchain-asset-receipt-vault-payment-mint-authorizer-v1");
bytes32 constant DEPLOYMENT_SUITE_STOX_CORPORATE_ACTIONS_FACET = keccak256("stox-corporate-actions-facet");

// =============================================================================
// V4 (rain.vats 0.1.6) suite ids. Re-deploy every ST0x contract whose source
// or dependency tree changed under the rain.vats bump. Each suite asserts
// against the corresponding `LibProdDeployV4` pin so a mid-deploy bytecode
// drift trips the codehash check before broadcast. Keep the v2/v3 entries
// above untouched — re-running a historical suite (e.g. for a fresh network)
// must remain possible.
// =============================================================================

bytes32 constant DEPLOYMENT_SUITE_STOX_RECEIPT_V4 = keccak256("stox-receipt-v4");
bytes32 constant DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT_V4 = keccak256("stox-receipt-vault-v4");
bytes32 constant DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_V4 = keccak256("stox-wrapped-token-vault-v4");
bytes32 constant DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_V4 = keccak256("stox-wrapped-token-vault-beacon-v4");
bytes32 constant DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_V4 =
    keccak256("stox-wrapped-token-vault-beacon-set-deployer-v4");
bytes32 constant DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_V4 =
    keccak256("stox-offchain-asset-receipt-vault-beacon-set-deployer-v4");
bytes32 constant DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER_V4 = keccak256("stox-unified-deployer-v4");
bytes32 constant DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_V4 =
    keccak256("stox-offchain-asset-receipt-vault-authorizer-v1-v4");
bytes32 constant DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_V4 =
    keccak256("stox-offchain-asset-receipt-vault-payment-mint-authorizer-v1-v4");
bytes32 constant DEPLOYMENT_SUITE_STOX_CORPORATE_ACTIONS_FACET_V4 = keccak256("stox-corporate-actions-facet-v4");

contract Deploy is Script {
    mapping(string => mapping(address => bytes32)) internal depCodeHashes;

    /// @dev Deploys a single contract via the Zoltu deterministic deployer
    /// across all supported networks. Reads `DEPLOYMENT_KEY` from the
    /// environment, logs diagnostic information (expected address, codehash,
    /// dependency state), then delegates to `LibRainDeploy.deployAndBroadcast`.
    /// @param creationCode The creation bytecode of the contract to deploy.
    /// @param contractPath Fully qualified contract path
    /// (e.g. "src/concrete/StoxReceipt.sol:StoxReceipt").
    /// @param expectedAddress The deterministic address the contract must
    /// deploy to.
    /// @param expectedCodeHash The expected codehash of the deployed runtime
    /// bytecode.
    /// @param dependencies Addresses of contracts that must already be deployed
    /// on the target network before this contract is deployed.
    function deploySuite(
        bytes memory creationCode,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        address[] memory dependencies
    ) internal {
        string[] memory networks = new string[](1);
        networks[0] = "base";
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
            address[] memory deps = new address[](2);
            deps[0] = LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER;
            deps[1] = LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER;
            deploySuite(
                type(StoxUnifiedDeployer).creationCode,
                "src/concrete/deploy/StoxUnifiedDeployer.sol:StoxUnifiedDeployer",
                LibProdDeployV2.STOX_UNIFIED_DEPLOYER,
                LibProdDeployV2.STOX_UNIFIED_DEPLOYER_CODEHASH,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1) {
            deploySuite(
                type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode,
                "src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol:StoxOffchainAssetReceiptVaultAuthorizerV1",
                LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1,
                LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1) {
            deploySuite(
                type(StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1).creationCode,
                "src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol:StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1",
                LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1,
                LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_CORPORATE_ACTIONS_FACET) {
            deploySuite(
                type(StoxCorporateActionsFacet).creationCode,
                "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
                LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_RAIN_VATS_0_1_6,
                LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_RAIN_VATS_0_1_6,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_RECEIPT_V4) {
            deploySuite(
                type(StoxReceipt).creationCode,
                "src/concrete/StoxReceipt.sol:StoxReceipt",
                LibProdDeployV4.STOX_RECEIPT_RAIN_VATS_0_1_6,
                LibProdDeployV4.STOX_RECEIPT_CODEHASH_RAIN_VATS_0_1_6,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT_V4) {
            deploySuite(
                type(StoxReceiptVault).creationCode,
                "src/concrete/StoxReceiptVault.sol:StoxReceiptVault",
                LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6,
                LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_RAIN_VATS_0_1_6,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_V4) {
            deploySuite(
                type(StoxWrappedTokenVault).creationCode,
                "src/concrete/StoxWrappedTokenVault.sol:StoxWrappedTokenVault",
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_RAIN_VATS_0_1_6,
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_CODEHASH_RAIN_VATS_0_1_6,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_V4) {
            address[] memory deps = new address[](1);
            deps[0] = LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_RAIN_VATS_0_1_6;
            deploySuite(
                type(StoxWrappedTokenVaultBeacon).creationCode,
                "src/concrete/StoxWrappedTokenVaultBeacon.sol:StoxWrappedTokenVaultBeacon",
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_RAIN_VATS_0_1_6,
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH_RAIN_VATS_0_1_6,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_V4) {
            address[] memory deps = new address[](1);
            deps[0] = LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_RAIN_VATS_0_1_6;
            deploySuite(
                type(StoxWrappedTokenVaultBeaconSetDeployer).creationCode,
                "src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol:StoxWrappedTokenVaultBeaconSetDeployer",
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6,
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH_RAIN_VATS_0_1_6,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_V4) {
            address[] memory deps = new address[](2);
            deps[0] = LibProdDeployV4.STOX_RECEIPT_RAIN_VATS_0_1_6;
            deps[1] = LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6;
            deploySuite(
                type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode,
                "src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol:StoxOffchainAssetReceiptVaultBeaconSetDeployer",
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6,
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH_RAIN_VATS_0_1_6,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER_V4) {
            address[] memory deps = new address[](2);
            deps[0] = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6;
            deps[1] = LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6;
            deploySuite(
                type(StoxUnifiedDeployer).creationCode,
                "src/concrete/deploy/StoxUnifiedDeployer.sol:StoxUnifiedDeployer",
                LibProdDeployV4.STOX_UNIFIED_DEPLOYER_RAIN_VATS_0_1_6,
                LibProdDeployV4.STOX_UNIFIED_DEPLOYER_CODEHASH_RAIN_VATS_0_1_6,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_V4) {
            deploySuite(
                type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode,
                "src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol:StoxOffchainAssetReceiptVaultAuthorizerV1",
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6,
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_RAIN_VATS_0_1_6,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_V4) {
            deploySuite(
                type(StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1).creationCode,
                "src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol:StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1",
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_RAIN_VATS_0_1_6,
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH_RAIN_VATS_0_1_6,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_CORPORATE_ACTIONS_FACET_V4) {
            deploySuite(
                type(StoxCorporateActionsFacet).creationCode,
                "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
                LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_RAIN_VATS_0_1_6,
                LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_RAIN_VATS_0_1_6,
                noDeps
            );
        } else {
            revert UnknownDeploymentSuite(suite);
        }
    }
}
