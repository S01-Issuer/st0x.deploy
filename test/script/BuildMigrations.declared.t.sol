// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "rain-deploy-0.1.29/src/interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.29/src/lib/LibMigrationRegistry.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";

import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

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

    function testEveryMigrationHasANamespaceAndAnId() external view {
        (string memory json, uint256 rows) = manifest();
        for (uint256 i = 0; i < rows; i++) {
            assertNotEq(namespaceOf(json, i), bytes32(0), row(i));
            assertNotEq(idOf(json, i), bytes32(0), row(i));
            assertNotEq(idOf(json, i), MIGRATION_HEAD_GENESIS, row(i));
        }
    }

    function testEveryWriterIsOneRoleOnEveryChain() external view {
        (string memory json, uint256 rows) = manifest();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < rows; i++) {
            assertEq(vm.parseJsonKeys(json, string.concat(row(i), ".chains")).length, nets.length, row(i));
            bool timelock =
                writerOf(json, i, nets[0].chainId) == LibTimelockInvariants.timelockForChainId(nets[0].chainId);
            for (uint256 n = 0; n < nets.length; n++) {
                uint256 chainId = nets[n].chainId;
                address expected = timelock
                    ? LibTimelockInvariants.timelockForChainId(chainId)
                    : LibSafeInvariants.safeForChainId(chainId);
                assertEq(writerOf(json, i, chainId), expected, chain(i, chainId));
            }
        }
    }

    function declared(string memory json, uint256 rows, uint256 chainId, Prerequisite memory prerequisite)
        internal
        pure
        returns (bool)
    {
        for (uint256 k = 0; k < rows; k++) {
            if (
                namespaceOf(json, k) == prerequisite.namespace && idOf(json, k) == prerequisite.migration
                    && writerOf(json, k, chainId) == prerequisite.writer
            ) return true;
        }
        return false;
    }

    function testEveryPrerequisiteIsGenesisOrADeclaredMigration() external view {
        (string memory json, uint256 rows) = manifest();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < rows; i++) {
            for (uint256 n = 0; n < nets.length; n++) {
                uint256 chainId = nets[n].chainId;
                Prerequisite[] memory prerequisites = prerequisitesOf(json, i, chainId);
                assertGt(prerequisites.length, 0, chain(i, chainId));
                for (uint256 j = 0; j < prerequisites.length; j++) {
                    if (j == 0 && prerequisites[0].migration == MIGRATION_HEAD_GENESIS) {
                        assertEq(prerequisites[0].writer, writerOf(json, i, chainId), chain(i, chainId));
                        assertEq(prerequisites[0].namespace, namespaceOf(json, i), chain(i, chainId));
                        continue;
                    }
                    assertTrue(declared(json, rows, chainId, prerequisites[j]), chain(i, chainId));
                }
            }
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
        uint256 executedAt = vm.parseJsonUint(json, string.concat(at, ".executedAt"));
        if (executedAt != 0) assertEq(applied, executedAt, at);
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
