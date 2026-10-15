// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {BuildMigrations} from "../../script/BuildMigrations.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations, Migration} from "../../src/lib/LibStoxMigrations.sol";

contract BuildMigrationsTest is Test {
    BuildMigrations internal build = new BuildMigrations();

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function testVersionIsOne() external {
        assertEq(vm.parseJsonUint(build.render(), ".version"), 1);
    }

    function testGenesisIsTheRegistryGenesis() external {
        assertEq(vm.parseJsonBytes32(build.render(), ".genesis"), MIGRATION_HEAD_GENESIS);
    }

    function testNetworksAreTheDeploymentNetworksWithTheRegistry() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        assertEq(vm.parseJsonKeys(json, ".networks").length, nets.length);
        for (uint256 i = 0; i < nets.length; i++) {
            string memory at = string.concat(".networks.", vm.toString(nets[i].chainId));
            assertEq(vm.parseJsonString(json, string.concat(at, ".network")), nets[i].name);
            assertEq(
                vm.parseJsonAddress(json, string.concat(at, ".registry")),
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS
            );
        }
    }

    function testMigrationsAreTheDeclaredList() external {
        string memory json = build.render();
        Migration[] memory list = LibStoxMigrations.migrations();
        assertFalse(vm.keyExistsJson(json, index(".migrations", list.length)));
        for (uint256 i = 0; i < list.length; i++) {
            string memory at = index(".migrations", i);
            assertEq(vm.parseJsonString(json, string.concat(at, ".script")), list[i].script);
            if (list[i].id == bytes32(0)) {
                assertJsonNull(json, string.concat(at, ".namespace"));
                assertJsonNull(json, string.concat(at, ".id"));
                assertEq(vm.parseJsonKeys(json, string.concat(at, ".chains")).length, 0);
            } else {
                assertEq(vm.parseJsonBytes32(json, string.concat(at, ".namespace")), list[i].namespace);
                assertEq(vm.parseJsonBytes32(json, string.concat(at, ".id")), list[i].id);
            }
        }
    }

    function testRecordedChainsAreTheResolvedWriterMomentAndPrerequisites() external {
        string memory json = build.render();
        Migration[] memory list = LibStoxMigrations.migrations();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].id == bytes32(0)) continue;
            string memory chains = string.concat(index(".migrations", i), ".chains");
            assertEq(vm.parseJsonKeys(json, chains).length, nets.length);
            for (uint256 c = 0; c < nets.length; c++) {
                uint256 chainId = nets[c].chainId;
                string memory at = string.concat(chains, ".", vm.toString(chainId));
                assertEq(
                    vm.parseJsonAddress(json, string.concat(at, ".writer")),
                    LibStoxMigrations.writerForChainId(list[i].writer, chainId)
                );
                assertEq(
                    vm.parseJsonUint(json, string.concat(at, ".executedAt")),
                    LibStoxMigrations.historyMoment(list[i].id, chainId)
                );
                Prerequisite[] memory expected = LibStoxMigrations.prerequisitesForChainId(list[i], chainId);
                string memory rows = string.concat(at, ".prerequisites");
                assertFalse(vm.keyExistsJson(json, index(rows, expected.length)));
                for (uint256 p = 0; p < expected.length; p++) {
                    string memory row = index(rows, p);
                    assertEq(vm.parseJsonAddress(json, string.concat(row, ".writer")), expected[p].writer);
                    assertEq(vm.parseJsonBytes32(json, string.concat(row, ".namespace")), expected[p].namespace);
                    assertEq(vm.parseJsonBytes32(json, string.concat(row, ".id")), expected[p].migration);
                }
            }
        }
    }

    function testRunWritesTheRender() external {
        vm.removeFile("migrations.json");
        build.run();
        assertEq(keccak256(vm.parseJson(vm.readFile("migrations.json"))), keccak256(vm.parseJson(build.render())));
    }

    /// @dev A null parses as `bytes32(0)` and stringifies as `null`; no string
    /// or hex value does both.
    function assertJsonNull(string memory json, string memory key) internal pure {
        assertEq(vm.parseJson(json, key), abi.encode(bytes32(0)), key);
        assertEq(vm.parseJsonString(json, key), "null", key);
    }

    function index(string memory at, uint256 i) internal pure returns (string memory) {
        return string.concat(at, "[", vm.toString(i), "]");
    }
}
