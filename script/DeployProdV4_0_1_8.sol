// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script, console2} from "forge-std-1.16.1/src/Script.sol";

import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";

/// @dev Error thrown when the DEPLOYMENT_SUITE env var does not match any known
/// suite.
error UnknownDeploymentSuite(bytes32 suite);

/// @dev Error thrown when the DEPLOYMENT_NETWORK env var does not match any
/// supported network.
error UnknownDeploymentNetwork(string network);

// One suite per contract to avoid Zoltu factory nonce issues.
//
// This script ships the audited 0.1.8 orchestrator set — the ST0x orchestrator
// and its on-chain dependency closure — to the selected network via the stored
// 0.1.8 creation bytecode. The 0.1.8 snapshot is the set the source at tag
// `sol-v0.1.14` (commit ed767bf2) compiles to byte-identically, which is the
// commit Protofire audited as `st0x.deploy 5.0` (July 2026). Each suite
// deploys the stored `LibProdDeployV4.*_CREATION_CODE_0_1_8` bytes and asserts
// against the `_0_1_8` address/codehash pins, so the on-chain result is the
// audited deployment regardless of what the current source compiles to.
//
// The closure is exactly what a working orchestrator needs on the target
// network and nothing more:
//
// - `ST0xOrchestrator.initialize` (and mint/burn) hard-revert via the
//   vault-logic version lock unless the 0.1.8
//   `StoxOffchainAssetReceiptVaultBeaconSetDeployer` it was built against is
//   on-chain, so that set-deployer must be deployed first.
// - The set-deployer's constructor bakes beacons over the 0.1.8 `StoxReceipt`
//   and `StoxReceiptVault` implementations, which must have code.
// - The 0.1.8 `StoxReceiptVault` `fallback()` delegatecalls the 0.1.8
//   `StoxCorporateActionsFacet`, so the facet must be on-chain before the
//   vault.
//
// The wrapped-token-vault chain, the authorizers and the unified deployer are
// deliberately absent: the orchestrator does not need them, and every
// network's production instances come from the audited 0.1.1 bootstrap set
// (`script/DeployProdV4_0_1_1.sol`). The 0.1.8 receipt is a byte-identical
// twin of the 0.1.1 receipt (same Zoltu address), so its suite is a no-op on
// a network that already carries the 0.1.1 set.

bytes32 constant DEPLOYMENT_SUITE_STOX_CORPORATE_ACTIONS_FACET = keccak256("stox-corporate-actions-facet");
bytes32 constant DEPLOYMENT_SUITE_STOX_RECEIPT = keccak256("stox-receipt");
bytes32 constant DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT = keccak256("stox-receipt-vault");
bytes32 constant DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER =
    keccak256("stox-offchain-asset-receipt-vault-beacon-set-deployer");
bytes32 constant DEPLOYMENT_SUITE_ST0X_ORCHESTRATOR = keccak256("st0x-orchestrator");
bytes32 constant DEPLOYMENT_SUITE_ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER =
    keccak256("st0x-orchestrator-beacon-set-deployer");

contract Deploy is Script {
    /// @dev Broadcasts a single contract via the Zoltu deterministic deployer
    /// on the selected network. Reads `DEPLOYMENT_KEY` from the environment,
    /// logs diagnostic information (expected address, codehash, dependency
    /// state), then delegates to `LibRainDeploy.deployAndBroadcast`.
    /// @param creationCode The creation bytecode of the contract to deploy.
    /// @param contractPath Fully qualified contract path
    /// (e.g. "src/concrete/ST0xOrchestrator.sol:ST0xOrchestrator").
    /// @param expectedAddress The deterministic address the contract must deploy
    /// to.
    /// @param expectedCodeHash The expected codehash of the deployed runtime
    /// bytecode.
    /// @param dependencies Addresses of contracts that must already be
    /// deployed on the selected network before this contract is deployed.
    function deploySuite(
        bytes memory creationCode,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        address[] memory dependencies
    ) internal {
        string[] memory networks = new string[](1);
        networks[0] = deploymentNetwork();
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");

        console2.log("Suite deploying (0.1.8):", contractPath);
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

    /// @notice The network the suite broadcasts to, from the
    /// `DEPLOYMENT_NETWORK` env var, validated against the supported set —
    /// Base (where the closure is already live, so a dispatch is an idempotent
    /// no-op) plus the two bootstrap networks. No default: an unset network
    /// reverts rather than silently picking a chain.
    /// @return network The validated `foundry.toml` rpc alias.
    function deploymentNetwork() internal view returns (string memory network) {
        network = vm.envOr("DEPLOYMENT_NETWORK", string(""));
        bytes32 networkHash = keccak256(bytes(network));
        if (
            networkHash != keccak256(bytes(LibRainDeploy.BASE))
                && networkHash != keccak256(bytes(LibStoxDeployNetworks.ETHEREUM))
                && networkHash != keccak256(bytes(LibStoxDeployNetworks.HYPEREVM))
        ) {
            revert UnknownDeploymentNetwork(network);
        }
    }

    /// @notice Entry point for the 0.1.8 orchestrator-set deployment script.
    /// @dev Requires env vars:
    /// - `DEPLOYMENT_KEY`: private key for the deployer account.
    /// - `DEPLOYMENT_SUITE`: which contract to deploy (e.g.
    ///   "st0x-orchestrator"). One contract per run.
    /// - `DEPLOYMENT_NETWORK`: network to ship to — `base`, `ethereum` or
    ///   `hyperevm`.
    function run() public {
        bytes32 suite = keccak256(bytes(vm.envString("DEPLOYMENT_SUITE")));
        address[] memory noDeps = new address[](0);

        if (suite == DEPLOYMENT_SUITE_STOX_CORPORATE_ACTIONS_FACET) {
            // StoxCorporateActionsFacet impl. No on-chain dependencies (the
            // receipt-vault impl hardcodes its address but does not link to it
            // at deploy time).
            deploySuite(
                LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CREATION_CODE_0_1_8,
                "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
                LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_8,
                LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_0_1_8,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_RECEIPT) {
            // Byte-identical twin of the 0.1.1 receipt (same Zoltu address) —
            // a no-op on any network that already carries the 0.1.1 set.
            deploySuite(
                LibProdDeployV4.STOX_RECEIPT_CREATION_CODE_0_1_8,
                "src/concrete/StoxReceipt.sol:StoxReceipt",
                LibProdDeployV4.STOX_RECEIPT_0_1_8,
                LibProdDeployV4.STOX_RECEIPT_CODEHASH_0_1_8,
                noDeps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT) {
            // StoxReceiptVault impl. Its `fallback()` delegatecalls the
            // hardcoded corporate-actions facet, and a delegatecall to a
            // code-less address silently no-ops — so the facet must already be
            // on-chain. Declared as a dependency so LibRainDeploy reverts
            // MissingDependency if the facet is not yet deployed on the
            // network.
            address[] memory deps = new address[](1);
            deps[0] = LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_8;
            deploySuite(
                LibProdDeployV4.STOX_RECEIPT_VAULT_CREATION_CODE_0_1_8,
                "src/concrete/StoxReceiptVault.sol:StoxReceiptVault",
                LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_8,
                LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_8,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER) {
            // Its constructor bakes beacons over the StoxReceipt and
            // StoxReceiptVault impls, both of which must already have code.
            address[] memory deps = new address[](2);
            deps[0] = LibProdDeployV4.STOX_RECEIPT_0_1_8;
            deps[1] = LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_8;
            deploySuite(
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_8,
                "src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol:StoxOffchainAssetReceiptVaultBeaconSetDeployer",
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_8,
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_8,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_ST0X_ORCHESTRATOR) {
            // ST0xOrchestrator impl. Parameterless constructor, so no
            // constructor dependency — but `initialize` (and mint/burn)
            // hard-revert via the vault-logic version lock unless the 0.1.8
            // OARV beacon-set deployer has code, so an orchestrator deployed
            // before it is guaranteed-inert. Declared as a dependency to
            // enforce the working order structurally.
            address[] memory deps = new address[](1);
            deps[0] = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_8;
            deploySuite(
                LibProdDeployV4.ST0X_ORCHESTRATOR_CREATION_CODE_0_1_8,
                "src/concrete/ST0xOrchestrator.sol:ST0xOrchestrator",
                LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_8,
                LibProdDeployV4.ST0X_ORCHESTRATOR_CODEHASH_0_1_8,
                deps
            );
        } else if (suite == DEPLOYMENT_SUITE_ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER) {
            // Its constructor bakes an `UpgradeableBeacon` over the
            // ST0xOrchestrator impl, which must already have code (OZ rejects
            // a code-less beacon implementation).
            address[] memory deps = new address[](1);
            deps[0] = LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_8;
            deploySuite(
                LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_8,
                "src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol:ST0xOrchestratorBeaconSetDeployer",
                LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_8,
                LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CODEHASH_0_1_8,
                deps
            );
        } else {
            revert UnknownDeploymentSuite(suite);
        }
    }
}
