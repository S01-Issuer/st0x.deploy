// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations, Migration} from "../src/lib/LibStoxMigrations.sol";

/// @title BuildMigrations
/// @notice Writes `migrations.json`: every migration a script performs, and per deployment network the registry
/// and, for a recorded migration, its writer, execution moment if recorded as history, and prerequisites.
contract BuildMigrations is Script {
    string internal constant PATH = "migrations.json";

    function prerequisitesJson(string memory key, Prerequisite[] memory prerequisites)
        internal
        returns (string[] memory)
    {
        string[] memory rows = new string[](prerequisites.length);
        for (uint256 i = 0; i < prerequisites.length; i++) {
            string memory row = string.concat(key, ".", vm.toString(i));
            vm.serializeAddress(row, "writer", prerequisites[i].writer);
            vm.serializeBytes32(row, "namespace", prerequisites[i].namespace);
            rows[i] = vm.serializeBytes32(row, "id", prerequisites[i].migration);
        }
        return rows;
    }

    function chainJson(string memory key, Migration memory migration, uint256 chainId)
        internal
        returns (string memory)
    {
        vm.serializeAddress(key, "writer", LibStoxMigrations.writerForChainId(migration.writer, chainId));
        vm.serializeUint(key, "executedAt", LibStoxMigrations.historyMoment(migration.id, chainId));
        return vm.serializeString(
            key,
            "prerequisites",
            prerequisitesJson(
                string.concat(key, ".prerequisites"), LibStoxMigrations.prerequisitesForChainId(migration, chainId)
            )
        );
    }

    function migrationJson(uint256 index, Migration memory migration, SupportedNetwork[] memory networks)
        internal
        returns (string memory)
    {
        string memory key = string.concat("migrations.", vm.toString(index));
        string memory chainsKey = string.concat(key, ".chains");
        string memory chains = vm.serializeJson(chainsKey, "{}");
        if (migration.id == bytes32(0)) {
            vm.serializeJson(key, "{\"namespace\":null,\"id\":null}");
        } else {
            vm.serializeBytes32(key, "namespace", migration.namespace);
            vm.serializeBytes32(key, "id", migration.id);
            for (uint256 i = 0; i < networks.length; i++) {
                string memory chainId = vm.toString(networks[i].chainId);
                chains = vm.serializeString(
                    chainsKey,
                    chainId,
                    chainJson(string.concat(chainsKey, ".", chainId), migration, networks[i].chainId)
                );
            }
        }
        vm.serializeString(key, "script", migration.script);
        return vm.serializeString(key, "chains", chains);
    }

    function render() public returns (string memory) {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        string memory networksJson;
        for (uint256 i = 0; i < networks.length; i++) {
            string memory key = string.concat("networks.", vm.toString(networks[i].chainId));
            vm.serializeString(key, "network", networks[i].name);
            networksJson = vm.serializeString(
                "networks",
                vm.toString(networks[i].chainId),
                vm.serializeAddress(key, "registry", LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            );
        }
        Migration[] memory migrations = LibStoxMigrations.migrations();
        string[] memory rows = new string[](migrations.length);
        for (uint256 i = 0; i < migrations.length; i++) {
            rows[i] = migrationJson(i, migrations[i], networks);
        }
        vm.serializeUint("root", "version", 1);
        vm.serializeBytes32("root", "genesis", MIGRATION_HEAD_GENESIS);
        vm.serializeString("root", "networks", networksJson);
        return vm.serializeString("root", "migrations", rows);
    }

    function run() external {
        vm.writeJson(render(), PATH);
    }
}
