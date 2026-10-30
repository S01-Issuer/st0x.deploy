// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_V3} from "rain-deploy-0.1.29/src/generated/0_1_25/ConfigRegistry.sol";
import {DEPLOYED_ADDRESS as MIGRATION_REGISTRY_V3} from "rain-deploy-0.1.29/src/generated/0_1_25/MigrationRegistry.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_V5} from "rain-deploy-0.1.29/src/generated/0_1_27/ConfigRegistry.sol";
import {DEPLOYED_ADDRESS as MIGRATION_REGISTRY_V5} from "rain-deploy-0.1.29/src/generated/0_1_27/MigrationRegistry.sol";
import {DEPLOYED_ADDRESS as CLONE_FACTORY_V5} from "rain-factory-deploy-0.2.4/src/generated/0_2_1/CloneFactory.sol";
import {DEPLOYED_ADDRESS as CLONE_FACTORY_V6} from "rain-factory-deploy-0.2.4/src/generated/0_2_2/CloneFactory.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {LibProdDeployV1} from "../src/lib/LibProdDeployV1.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @title BuildSubgraphNetworks
/// @notice Writes `subgraph/networks.json`: every data source address from its pin, keeping each committed
/// `startBlock`, which is chain history and has no pin. Each clone factory version is its own data source, pinned to
/// that release's frozen snapshot, so a new version adds a source and the old ones keep indexing.
contract BuildSubgraphNetworks is Script {
    string internal constant PATH = "subgraph/networks.json";

    string[14] internal NAMES = [
        "Authorizer",
        "CloneFactoryV5",
        "CloneFactoryV6",
        "ConfigRegistry",
        "ConfigRegistryV5",
        "EuAuthorizer",
        "GovernanceTimelock",
        "MigrationRegistry",
        "MigrationRegistryV5",
        "OrchestratorBeacon",
        "OrchestratorDeployer",
        "ReceiptVaultDeployer",
        "TokenOwnerSafe",
        "WrappedTokenVaultBeacon"
    ];

    /// The Graph's id for chain 1 is `mainnet`; every other deployment network's id is its foundry alias.
    function graphNetwork(SupportedNetwork memory network) public pure returns (string memory) {
        return network.chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID ? "mainnet" : network.name;
    }

    function addresses(uint256 chainId) public pure returns (address[14] memory) {
        address[4] memory beacons = LibBeaconInvariants.prodPinnedBeaconsForChainId(chainId);
        address receiptVaultDeployer = LibBeaconInvariants.prodBeaconSetDeployerForChainId(chainId);
        return [
            LibAuthoriserInvariants.authoriserForChainId(chainId),
            CLONE_FACTORY_V5,
            CLONE_FACTORY_V6,
            CONFIG_REGISTRY_V3,
            CONFIG_REGISTRY_V5,
            LibAuthoriserInvariants.euAuthoriserForChainId(chainId),
            LibTimelockInvariants.timelockForChainId(chainId),
            MIGRATION_REGISTRY_V3,
            MIGRATION_REGISTRY_V5,
            beacons[3],
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30,
            receiptVaultDeployer == address(0)
                ? LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
                : receiptVaultDeployer,
            LibSafeInvariants.safeForChainId(chainId),
            beacons[2]
        ];
    }

    function render(string memory current) public returns (string memory) {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        string memory root;
        for (uint256 i = 0; i < networks.length; i++) {
            string memory network = graphNetwork(networks[i]);
            address[14] memory pins = addresses(networks[i].chainId);
            string memory sources;
            for (uint256 j = 0; j < NAMES.length; j++) {
                string memory key = string.concat(network, ".", NAMES[j]);
                vm.serializeAddress(key, "address", pins[j]);
                string memory source = vm.serializeUint(
                    key, "startBlock", vm.parseJsonUint(current, string.concat(".", key, ".startBlock"))
                );
                sources = vm.serializeString(network, NAMES[j], source);
            }
            root = vm.serializeString("root", network, sources);
        }
        return root;
    }

    function run() external {
        vm.writeJson(render(vm.readFile(PATH)), PATH);
    }
}
