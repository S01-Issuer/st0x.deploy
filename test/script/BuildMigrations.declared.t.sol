// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "rain-deploy-0.1.25/src/interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.25/src/lib/LibMigrationRegistry.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.25/src/lib/LibRainDeploy.sol";

import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibMigrationLineFork} from "../lib/LibMigrationLineFork.sol";

/// @title BuildMigrationsDeclaredTest
/// @notice Every migration the scripts declare, read from `migrations.json`
/// (git-clean regenerates it from `script/` and fails on any drift).
contract BuildMigrationsDeclaredTest is Test {
    string internal constant MANIFEST = "migrations.json";

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function index(string memory at, uint256 i) internal pure returns (string memory) {
        return string.concat(at, "[", vm.toString(i), "]");
    }

    function count(string memory json, string memory at) internal view returns (uint256 n) {
        while (vm.keyExistsJson(json, index(at, n))) n++;
    }

    function row(uint256 i) internal pure returns (string memory) {
        return index(".migrations", i);
    }

    function chain(uint256 i, uint256 chainId) internal pure returns (string memory) {
        return string.concat(row(i), ".chains.", vm.toString(chainId));
    }

    function namespaceOf(string memory json, uint256 i) internal pure returns (bytes32) {
        return vm.parseJsonBytes32(json, string.concat(row(i), ".namespace"));
    }

    function idOf(string memory json, uint256 i) internal pure returns (bytes32) {
        return vm.parseJsonBytes32(json, string.concat(row(i), ".id"));
    }

    function writerOf(string memory json, uint256 i, uint256 chainId) internal pure returns (address) {
        return vm.parseJsonAddress(json, string.concat(chain(i, chainId), ".writer"));
    }

    function prerequisitesOf(string memory json, uint256 i, uint256 chainId)
        internal
        view
        returns (Prerequisite[] memory prerequisites)
    {
        string memory at = string.concat(chain(i, chainId), ".prerequisites");
        prerequisites = new Prerequisite[](count(json, at));
        for (uint256 j = 0; j < prerequisites.length; j++) {
            string memory pre = index(at, j);
            prerequisites[j] = Prerequisite({
                writer: vm.parseJsonAddress(json, string.concat(pre, ".writer")),
                namespace: vm.parseJsonBytes32(json, string.concat(pre, ".namespace")),
                migration: vm.parseJsonBytes32(json, string.concat(pre, ".id"))
            });
        }
    }

    function manifest() internal view returns (string memory json, uint256 rows) {
        json = vm.readFile(MANIFEST);
        rows = count(json, ".migrations");
        assertGt(rows, 0);
    }

    function testEveryMigrationIsKeyedByItsScriptInTheNamespace() external view {
        (string memory json, uint256 rows) = manifest();
        for (uint256 i = 0; i < rows; i++) {
            assertEq(namespaceOf(json, i), LibStoxMigrations.NAMESPACE, row(i));
            assertEq(
                idOf(json, i), keccak256(bytes(vm.parseJsonString(json, string.concat(row(i), ".script")))), row(i)
            );
        }
    }

    /// @notice Every chain of every record is the root authority's, executed
    /// with its change, onto one head in its own line.
    function testEveryRecordIsInTheRootLineOnEveryChain() external view {
        (string memory json, uint256 rows) = manifest();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < rows; i++) {
            assertEq(vm.parseJsonKeys(json, string.concat(row(i), ".chains")).length, nets.length, row(i));
            bytes32 head = prerequisitesOf(json, i, nets[0].chainId)[0].migration;
            for (uint256 n = 0; n < nets.length; n++) {
                uint256 chainId = nets[n].chainId;
                string memory at = chain(i, chainId);
                assertEq(writerOf(json, i, chainId), LibStoxMigrations.WRITER, at);
                assertEq(vm.parseJsonUint(json, string.concat(at, ".executedAt")), 0, at);
                Prerequisite[] memory prerequisites = prerequisitesOf(json, i, chainId);
                assertEq(prerequisites.length, 1, at);
                assertEq(prerequisites[0].writer, LibStoxMigrations.WRITER, at);
                assertEq(prerequisites[0].namespace, LibStoxMigrations.NAMESPACE, at);
                assertEq(prerequisites[0].migration, head, at);
            }
        }
    }

    function headOf(string memory json, uint256 i) internal view returns (bytes32) {
        return prerequisitesOf(json, i, networks()[0].chainId)[0].migration;
    }

    /// @notice Following the heads from genesis visits every record once, in
    /// the line's order.
    function testTheRecordsAreTheLineInOrderFromGenesis() external view {
        (string memory json, uint256 rows) = manifest();
        assertEq(rows, LibMigrationLineFork.line().length, "every migration is in the line");
        bytes32 at = MIGRATION_HEAD_GENESIS;
        for (uint256 visited = 0; visited < rows; visited++) {
            uint256 next = rows;
            for (uint256 i = 0; i < rows; i++) {
                if (headOf(json, i) != at) continue;
                assertEq(next, rows, "two records onto one head");
                next = i;
            }
            assertLt(next, rows, "the line stops before every record");
            assertEq(idOf(json, next), LibMigrationLineFork.line()[visited].id);
            at = idOf(json, next);
        }
        for (uint256 i = 0; i < rows; i++) {
            assertNotEq(headOf(json, i), at, "a record onto the line's last");
        }
    }

    function testEveryAppliedRecordIsItsDeclaration() external {
        (string memory json, uint256 rows) = manifest();
        SupportedNetwork[] memory nets = networks();
        for (uint256 n = 0; n < nets.length; n++) {
            vm.createSelectFork(nets[n].name);
            for (uint256 i = 0; i < rows; i++) {
                assertApplied(json, i, nets[n].chainId);
            }
        }
    }

    function assertApplied(string memory json, uint256 i, uint256 chainId) internal view {
        address writer = writerOf(json, i, chainId);
        uint256 applied = LibMigrationRegistry.appliedV3(writer, namespaceOf(json, i), idOf(json, i));
        if (applied == 0) return;
        string memory at = chain(i, chainId);
        Prerequisite[] memory expected = prerequisitesOf(json, i, chainId);
        Prerequisite[] memory actual = LibMigrationRegistry.appliedAfterV3(writer, namespaceOf(json, i), idOf(json, i));
        assertEq(actual.length, expected.length, at);
        for (uint256 j = 0; j < expected.length; j++) {
            assertEq(actual[j].writer, expected[j].writer, at);
            assertEq(actual[j].namespace, expected[j].namespace, at);
            assertEq(actual[j].migration, expected[j].migration, at);
        }
    }
}
