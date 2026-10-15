// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IMigrationRegistryV2, Prerequisite} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.18/src/lib/LibSafeTx.sol";

import {GrantEuAuthoriserRoles} from "../../../script/20261006-grant-eu-authoriser-roles.s.sol";
import {LibEuAuthoriserClone} from "../../../src/lib/LibEuAuthoriserClone.sol";
import {LibRbacMigration} from "../../../src/lib/LibRbacMigration.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {
    LibStoxMigrations,
    Migration,
    MigrationPrerequisite,
    MigrationWriter
} from "../../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {GrantOrchestratorEmergencyHarness} from "../../script/GrantOrchestratorEmergencyHarness.sol";
import {OrchestratorAdminToTimelockHarness} from "../../script/OrchestratorAdminToTimelockHarness.sol";

struct RegistryWrite {
    address writer;
    bytes32 namespace;
    bytes32 migration;
    uint256 appliedAt;
    Prerequisite[] prerequisites;
}

/// @title LibStoxMigrationsListTest
/// @notice `migrations()` is every migration script, each recorded one carries
/// the id, namespace, writer, prerequisites and history moment its script's
/// bundle writes, and an executed record reads back the same prerequisites.
contract LibStoxMigrationsListTest is Test {
    /// @dev Deploy and timelock-rehearsal scripts: they change no live
    /// contract's ownership, roles or configuration.
    function notMigrations() internal pure returns (string[] memory) {
        string[] memory list = new string[](6);
        list[0] = "script/20260729-deploy-governance-timelock.s.sol";
        list[1] = "script/20260807-deploy-missing-tokens.s.sol";
        list[2] = "script/20260813-execute-timelock-operations.s.sol";
        list[3] = "script/20260813-timelock-rehearsal-cancel.s.sol";
        list[4] = "script/20260813-timelock-rehearsal-schedule.s.sol";
        list[5] = "script/20261006-deploy-eu-authoriser.s.sol";
        return list;
    }

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function endsWith(string memory s, string memory suffix) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(suffix);
        if (a.length < b.length) return false;
        for (uint256 i = 0; i < b.length; i++) {
            if (a[a.length - b.length + i] != b[i]) return false;
        }
        return true;
    }

    function testEveryScriptIsClassifiedOnce() external view {
        Migration[] memory list = LibStoxMigrations.migrations();
        string[] memory others = notMigrations();
        Vm.DirEntry[] memory entries = vm.readDir("script", 1);
        uint256 scripts = 0;
        for (uint256 e = 0; e < entries.length; e++) {
            if (entries[e].isDir || !endsWith(entries[e].path, ".s.sol")) continue;
            scripts++;
            uint256 hits = 0;
            for (uint256 i = 0; i < list.length; i++) {
                if (endsWith(entries[e].path, string.concat("/", list[i].script))) hits++;
            }
            for (uint256 i = 0; i < others.length; i++) {
                if (endsWith(entries[e].path, string.concat("/", others[i]))) hits++;
            }
            assertEq(hits, 1, entries[e].path);
        }
        assertEq(list.length + others.length, scripts, "a classified script is not in script/");
    }

    function testRecordedIdsAreTheLibraryIds() external pure {
        bytes32[4] memory ids = [
            LibStoxMigrations.GOVERNANCE_TIMELOCK,
            LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
            LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
            LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER
        ];
        bytes32[4] memory namespaces = [
            LibStoxMigrations.NAMESPACE,
            LibStoxMigrations.NAMESPACE,
            LibStoxMigrations.NAMESPACE,
            LibRbacMigration.STOX_RBAC_NAMESPACE
        ];
        Migration[] memory list = LibStoxMigrations.migrations();
        uint256 recorded = 0;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].id == bytes32(0)) continue;
            recorded++;
            uint256 hits = 0;
            for (uint256 j = 0; j < ids.length; j++) {
                if (list[i].id == ids[j]) {
                    hits++;
                    assertEq(list[i].namespace, namespaces[j], list[i].script);
                }
            }
            assertEq(hits, 1, list[i].script);
        }
        assertEq(recorded, ids.length);
    }

    function testDeployIdsAreTheirScriptPaths() external pure {
        Migration[] memory list = LibStoxMigrations.migrations();
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].namespace == LibStoxMigrations.NAMESPACE) {
                assertEq(list[i].id, keccak256(bytes(list[i].script)), list[i].script);
            }
        }
    }

    function testUnrecordedCarryNoRecord() external pure {
        Migration[] memory list = LibStoxMigrations.migrations();
        uint256 unrecorded = 0;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].id != bytes32(0)) continue;
            unrecorded++;
            assertEq(list[i].namespace, bytes32(0), list[i].script);
            assertEq(list[i].prerequisites.length, 0, list[i].script);
        }
        assertEq(unrecorded, 2);
    }

    function testWriterForChainIdIsTheChainsSafeOrTimelock() external pure {
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            uint256 chainId = nets[i].chainId;
            assertEq(
                LibStoxMigrations.writerForChainId(MigrationWriter.Safe, chainId),
                LibSafeInvariants.safeForChainId(chainId)
            );
            assertEq(
                LibStoxMigrations.writerForChainId(MigrationWriter.Timelock, chainId),
                LibTimelockInvariants.timelockForChainId(chainId)
            );
        }
    }

    function testPrerequisitesForChainIdResolveEachWriter() external pure {
        MigrationPrerequisite[] memory declared = new MigrationPrerequisite[](2);
        declared[0] = MigrationPrerequisite({writer: MigrationWriter.Timelock, namespace: "a", migration: "b"});
        declared[1] = MigrationPrerequisite({writer: MigrationWriter.Safe, namespace: "c", migration: "d"});
        Migration memory migration =
            Migration({script: "", namespace: "a", id: "e", writer: MigrationWriter.Timelock, prerequisites: declared});
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            Prerequisite[] memory resolved = LibStoxMigrations.prerequisitesForChainId(migration, nets[i].chainId);
            assertEq(resolved.length, 2);
            assertEq(resolved[0].writer, LibTimelockInvariants.timelockForChainId(nets[i].chainId));
            assertEq(resolved[0].namespace, "a");
            assertEq(resolved[0].migration, "b");
            assertEq(resolved[1].writer, LibSafeInvariants.safeForChainId(nets[i].chainId));
            assertEq(resolved[1].namespace, "c");
            assertEq(resolved[1].migration, "d");
        }
    }

    function decodeWrite(bytes calldata data) external pure returns (RegistryWrite memory) {
        RegistryWrite memory write;
        bytes4 selector = bytes4(data[:4]);
        if (selector == IMigrationRegistryV2.applyMigration.selector) {
            (write.namespace, write.migration, write.prerequisites) =
                abi.decode(data[4:], (bytes32, bytes32, Prerequisite[]));
        } else {
            assertEq(selector, IMigrationRegistryV2.applyMigrationHistory.selector);
            (write.namespace, write.migration, write.appliedAt, write.prerequisites) =
                abi.decode(data[4:], (bytes32, bytes32, uint256, Prerequisite[]));
        }
        return write;
    }

    /// @dev Every registry call in the bundles that write this repo's records.
    function bundleWrites(string memory network) internal returns (RegistryWrite[] memory) {
        GrantOrchestratorEmergencyHarness emergency = new GrantOrchestratorEmergencyHarness(network);
        OrchestratorAdminToTimelockHarness admin = new OrchestratorAdminToTimelockHarness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        SafeTx[][3] memory bundles = [
            emergency.callAuthorBundle(),
            admin.callAuthorBundle(),
            new GrantEuAuthoriserRoles()
                .grantBundle(
                    LibEuAuthoriserClone.cloneDeployedAddress(block.chainid),
                    safe,
                    LibTimelockInvariants.timelockForChainId(block.chainid)
                )
        ];
        address[3] memory signers = [emergency.callSafe(), admin.callSafe(), safe];

        uint256 count = 0;
        for (uint256 b = 0; b < bundles.length; b++) {
            for (uint256 t = 0; t < bundles[b].length; t++) {
                if (bundles[b][t].to == LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS) count++;
            }
        }
        RegistryWrite[] memory writes = new RegistryWrite[](count);
        uint256 w = 0;
        for (uint256 b = 0; b < bundles.length; b++) {
            for (uint256 t = 0; t < bundles[b].length; t++) {
                if (bundles[b][t].to != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS) continue;
                writes[w] = this.decodeWrite(bundles[b][t].data);
                writes[w].writer = signers[b];
                w++;
            }
        }
        return writes;
    }

    function assertPrerequisites(Prerequisite[] memory actual, Prerequisite[] memory expected, string memory label)
        internal
        pure
    {
        assertEq(actual.length, expected.length, label);
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(actual[i].writer, expected[i].writer, label);
            assertEq(actual[i].namespace, expected[i].namespace, label);
            assertEq(actual[i].migration, expected[i].migration, label);
        }
    }

    function assertRecordsAreTheBundles(string memory network) internal {
        vm.createSelectFork(network);
        RegistryWrite[] memory writes = bundleWrites(network);
        Migration[] memory list = LibStoxMigrations.migrations();
        uint256 recorded = 0;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].id == bytes32(0)) continue;
            recorded++;
            string memory label = string.concat(network, ": ", list[i].script);
            address writer = LibStoxMigrations.writerForChainId(list[i].writer, block.chainid);
            Prerequisite[] memory declared = LibStoxMigrations.prerequisitesForChainId(list[i], block.chainid);
            uint256 hits = 0;
            for (uint256 w = 0; w < writes.length; w++) {
                if (writes[w].namespace != list[i].namespace || writes[w].migration != list[i].id) continue;
                hits++;
                assertEq(writes[w].writer, writer, label);
                assertEq(writes[w].appliedAt, LibStoxMigrations.historyMoment(list[i].id, block.chainid), label);
                assertPrerequisites(writes[w].prerequisites, declared, label);
            }
            assertEq(hits, 1, label);
            if (LibMigrationRegistry.applied(writer, list[i].namespace, list[i].id) != 0) {
                assertPrerequisites(
                    LibMigrationRegistry.appliedAfter(writer, list[i].namespace, list[i].id), declared, label
                );
            }
        }
        assertEq(writes.length, recorded, network);
    }

    function testRecordsAreTheBundlesBase() external {
        assertRecordsAreTheBundles(LibRainDeploy.BASE);
    }

    function testRecordsAreTheBundlesEthereum() external {
        assertRecordsAreTheBundles(LibStoxDeployNetworks.ETHEREUM);
    }

    function testRecordsAreTheBundlesHyperEvm() external {
        assertRecordsAreTheBundles(LibStoxDeployNetworks.HYPEREVM);
    }

    function testRecordsAreTheBundlesRobinhood() external {
        assertRecordsAreTheBundles(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testRecordsAreTheBundlesBsc() external {
        assertRecordsAreTheBundles(LibStoxDeployNetworks.BSC);
    }
}
