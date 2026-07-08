// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script, console2} from "forge-std-1.16.1/src/Script.sol";

import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {LibProdDeployV4} from "../src/lib/LibProdDeployV4.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
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
import {ST0xOrchestrator} from "../src/concrete/ST0xOrchestrator.sol";
import {ST0xOrchestratorBeaconSetDeployer} from "../src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol";

/// @dev Error thrown when the DEPLOYMENT_SUITE env var does not match any
/// known suite.
error UnknownDeploymentSuite(bytes32 suite);

// One suite per contract to avoid Zoltu factory nonce issues.
//
// Suite ids carry no version: the deploy script itself handles versioning, so a
// suite is stable across releases and always deploys the current source. Each
// suite asserts against the corresponding `LibProdDeployV4` pin for the current
// release (0.1.3) so a mid-deploy bytecode drift trips the codehash check
// before broadcast. A historical tag only needs deploying once and is kept for
// downstream consumers. The frozen pre-V4 deployments live in `LibProdDeployV1`
// / `LibProdDeployV2` as an audit trail and are not redeployable from the
// current source.

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
bytes32 constant DEPLOYMENT_SUITE_ST0X_ORCHESTRATOR = keccak256("st0x-orchestrator");
bytes32 constant DEPLOYMENT_SUITE_ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER =
    keccak256("st0x-orchestrator-beacon-set-deployer");

contract Deploy is Script {
    /// @dev Deploys a single contract via the Zoltu deterministic deployer on
    /// Base. Reads `DEPLOYMENT_KEY` from the environment, logs diagnostic
    /// information (expected address, codehash, dependency state), then
    /// delegates to `LibRainDeploy.deployAndBroadcast`.
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
        string[] memory networks = LibStoxDeployNetworks.supportedNetworks();
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
            dependencies
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
                LibProdDeployV4.STOX_RECEIPT_0_1_3,
                LibProdDeployV4.STOX_RECEIPT_CODEHASH_0_1_3,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT) {
            // StoxReceiptVault impl. Its `fallback()` delegatecalls the
            // hardcoded corporate-actions facet, and a delegatecall to a
            // code-less address silently no-ops — so the facet must already be
            // on-chain. Declare it as a dependency: LibRainDeploy reverts
            // MissingDependency if the facet is not yet deployed on the target
            // network, enforcing the order structurally rather than by runbook.
            address[] memory deps = new address[](1);
            deps[0] = LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_3;
            deploySuite(
                type(StoxReceiptVault).creationCode,
                "src/concrete/StoxReceiptVault.sol:StoxReceiptVault",
                LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_3,
                LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_3,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT) {
            deploySuite(
                type(StoxWrappedTokenVault).creationCode,
                "src/concrete/StoxWrappedTokenVault.sol:StoxWrappedTokenVault",
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_3,
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_CODEHASH_0_1_3,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON) {
            address[] memory deps = new address[](1);
            deps[0] = LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_3;
            deploySuite(
                type(StoxWrappedTokenVaultBeacon).creationCode,
                "src/concrete/StoxWrappedTokenVaultBeacon.sol:StoxWrappedTokenVaultBeacon",
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_3,
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH_0_1_3,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER) {
            address[] memory deps = new address[](1);
            deps[0] = LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_3;
            deploySuite(
                type(StoxWrappedTokenVaultBeaconSetDeployer).creationCode,
                "src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol:StoxWrappedTokenVaultBeaconSetDeployer",
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_3,
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_3,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER) {
            // Its constructor bakes beacons over the StoxReceipt and
            // StoxReceiptVault impls, both of which must already have code.
            address[] memory deps = new address[](2);
            deps[0] = LibProdDeployV4.STOX_RECEIPT_0_1_3;
            deps[1] = LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_3;
            deploySuite(
                type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode,
                "src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol:StoxOffchainAssetReceiptVaultBeaconSetDeployer",
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_3,
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_3,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER) {
            // Embeds the OARV beacon-set deployer and the wrapped-token-vault
            // beacon-set deployer it drives; both must already have code.
            address[] memory deps = new address[](2);
            deps[0] = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_3;
            deps[1] = LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_3;
            deploySuite(
                type(StoxUnifiedDeployer).creationCode,
                "src/concrete/deploy/StoxUnifiedDeployer.sol:StoxUnifiedDeployer",
                LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_3,
                LibProdDeployV4.STOX_UNIFIED_DEPLOYER_CODEHASH_0_1_3,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1) {
            deploySuite(
                type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode,
                "src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol:StoxOffchainAssetReceiptVaultAuthorizerV1",
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_3,
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_0_1_3,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1) {
            deploySuite(
                type(StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1).creationCode,
                "src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol:StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1",
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_0_1_3,
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH_0_1_3,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_CORPORATE_ACTIONS_FACET) {
            // StoxCorporateActionsFacet impl. No on-chain dependencies (the
            // receipt-vault impl hardcodes its address but does not link to it
            // at deploy time).
            deploySuite(
                type(StoxCorporateActionsFacet).creationCode,
                "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
                LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_3,
                LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_0_1_3,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_ST0X_ORCHESTRATOR) {
            // ST0xOrchestrator impl — parameterless (Initializable), depends on
            // nothing at deploy time. Embeds the OARV beacon-set deployer and
            // receipt-vault addresses, checked at runtime.
            deploySuite(
                type(ST0xOrchestrator).creationCode,
                "src/concrete/ST0xOrchestrator.sol:ST0xOrchestrator",
                LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_3,
                LibProdDeployV4.ST0X_ORCHESTRATOR_CODEHASH_0_1_3,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER) {
            // Its constructor bakes a beacon over the ST0xOrchestrator impl,
            // which must already have code.
            address[] memory deps = new address[](1);
            deps[0] = LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_3;
            deploySuite(
                type(ST0xOrchestratorBeaconSetDeployer).creationCode,
                "src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol:ST0xOrchestratorBeaconSetDeployer",
                LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_3,
                LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CODEHASH_0_1_3,
                deps
            );
        } else {
            revert UnknownDeploymentSuite(suite);
        }
    }
}
