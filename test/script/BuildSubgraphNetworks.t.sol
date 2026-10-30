// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_V3} from "rain-deploy-0.1.29/src/generated/0_1_25/ConfigRegistry.sol";
import {DEPLOYED_ADDRESS as MIGRATION_REGISTRY_V3} from "rain-deploy-0.1.29/src/generated/0_1_25/MigrationRegistry.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_V5} from "rain-deploy-0.1.29/src/generated/0_1_27/ConfigRegistry.sol";
import {DEPLOYED_ADDRESS as MIGRATION_REGISTRY_V5} from "rain-deploy-0.1.29/src/generated/0_1_27/MigrationRegistry.sol";
import {DEPLOYED_ADDRESS as CLONE_FACTORY_V5} from "rain-factory-deploy-0.2.4/src/generated/0_2_1/CloneFactory.sol";
import {DEPLOYED_ADDRESS as CLONE_FACTORY_V6} from "rain-factory-deploy-0.2.4/src/generated/0_2_2/CloneFactory.sol";
import {LibCloneFactoryDeploy} from "rain-factory-deploy-0.2.4/src/lib/LibCloneFactoryDeploy.sol";
import {BuildSubgraphNetworks} from "../../script/BuildSubgraphNetworks.sol";
import {LibProdDeployV1} from "../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

contract BuildSubgraphNetworksTest is Test {
    BuildSubgraphNetworks internal build = new BuildSubgraphNetworks();

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function committed() internal view returns (string memory) {
        return vm.readFile("subgraph/networks.json");
    }

    function at(string memory json, string memory network, string memory source) internal pure returns (address) {
        return vm.parseJsonAddress(json, string.concat(".", network, ".", source, ".address"));
    }

    function testNetworksAreTheDeploymentNetworksByGraphId() external {
        string memory json = build.render(committed());
        SupportedNetwork[] memory nets = networks();
        assertEq(vm.parseJsonKeys(json, ".").length, nets.length);
        for (uint256 i = 0; i < nets.length; i++) {
            assertEq(vm.parseJsonKeys(json, string.concat(".", build.graphNetwork(nets[i]))).length, 14);
        }
    }

    function testRegistriesAndFactoryAreThePinnedDependencyDeploys() external {
        string memory json = build.render(committed());
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            string memory n = build.graphNetwork(nets[i]);
            assertEq(at(json, n, "ConfigRegistry"), CONFIG_REGISTRY_V3);
            assertEq(at(json, n, "MigrationRegistry"), MIGRATION_REGISTRY_V3);
            assertEq(at(json, n, "ConfigRegistryV5"), CONFIG_REGISTRY_V5);
            assertEq(at(json, n, "MigrationRegistryV5"), MIGRATION_REGISTRY_V5);
            assertEq(at(json, n, "CloneFactoryV5"), CLONE_FACTORY_V5);
            assertEq(at(json, n, "CloneFactoryV6"), CLONE_FACTORY_V6);
        }
    }

    /// A rain-factory-deploy bump that moves the factory fails here until the
    /// new version is its own data source.
    function testNewestFactorySourceIsThePinnedFactory() external pure {
        assertEq(CLONE_FACTORY_V6, LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS);
    }

    function testPrincipalsAreTheChainsPins() external {
        string memory json = build.render(committed());
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            uint256 id = nets[i].chainId;
            string memory n = build.graphNetwork(nets[i]);
            assertEq(at(json, n, "Authorizer"), LibAuthoriserInvariants.authoriserForChainId(id));
            assertEq(at(json, n, "EuAuthorizer"), LibAuthoriserInvariants.euAuthoriserForChainId(id));
            assertEq(at(json, n, "GovernanceTimelock"), LibTimelockInvariants.timelockForChainId(id));
            assertEq(at(json, n, "TokenOwnerSafe"), LibSafeInvariants.safeForChainId(id));
            assertEq(at(json, n, "OrchestratorBeacon"), LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON);
            assertEq(at(json, n, "OrchestratorDeployer"), LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30);
        }
    }

    function testBaseRunsTheV1BeaconSet() external {
        string memory json = build.render(committed());
        assertEq(
            at(json, "base", "ReceiptVaultDeployer"), LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
        );
        assertEq(at(json, "base", "WrappedTokenVaultBeacon"), LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1);
    }

    function testOtherChainsRunThe011BeaconSet() external {
        string memory json = build.render(committed());
        string[4] memory others = ["mainnet", "hyperevm", "robinhood", "bsc"];
        for (uint256 i = 0; i < others.length; i++) {
            assertEq(
                at(json, others[i], "ReceiptVaultDeployer"),
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1
            );
            assertEq(
                at(json, others[i], "WrappedTokenVaultBeacon"), LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1
            );
        }
    }

    function testStartBlocksCarryOverAndAddressesDoNot() external {
        string memory json = build.render(
            vm.replace(committed(), vm.toString(LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON), vm.toString(address(0xdead)))
        );
        assertEq(at(json, "bsc", "OrchestratorBeacon"), LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON);
        string memory edited = vm.replace(committed(), "\"startBlock\": 121143012", "\"startBlock\": 7");
        assertEq(vm.parseJsonUint(build.render(edited), ".bsc.OrchestratorBeacon.startBlock"), 7);
    }
}
