// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IMigrationRegistryV2, Prerequisite} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.18/src/lib/LibSafeTx.sol";

import {BuildMigrations} from "../../../script/BuildMigrations.sol";
import {GrantEuAuthoriserRoles} from "../../../script/20261006-grant-eu-authoriser-roles.s.sol";
import {
    IStoxHistoryMigration,
    MigrationPrerequisite,
    MigrationWriter,
    ScriptDeclaration,
    ScriptKind
} from "../../../src/interface/IStoxScript.sol";
import {LibEuAuthoriserClone} from "../../../src/lib/LibEuAuthoriserClone.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../../src/lib/LibStoxMigrations.sol";
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

/// @title LibStoxMigrationsDeclarationsTest
/// @notice The declaration helpers resolve roles to each chain's Safe and
/// timelock, and every migration a script declares is written by exactly one
/// bundle, with the writer, prerequisites and moment it declares.
contract LibStoxMigrationsDeclarationsTest is Test {
    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function testSafeMigrationOntoIsOneSafePrerequisiteInItsOwnNamespace() external pure {
        ScriptDeclaration memory d = LibStoxMigrations.safeMigrationOnto("ns", "id", "head", true);
        assertEq(uint256(d.kind), uint256(ScriptKind.Migration));
        assertEq(d.namespace, "ns");
        assertEq(d.id, "id");
        assertEq(uint256(d.writer), uint256(MigrationWriter.Safe));
        assertTrue(d.history);
        assertEq(d.prerequisites.length, 1);
        assertEq(uint256(d.prerequisites[0].writer), uint256(MigrationWriter.Safe));
        assertEq(d.prerequisites[0].namespace, "ns");
        assertEq(d.prerequisites[0].migration, "head");
        assertFalse(LibStoxMigrations.safeMigrationOnto("ns", "id", "head", false).history);
    }

    function testNotAMigrationCarriesNoRecord() external pure {
        ScriptDeclaration memory d = LibStoxMigrations.notAMigration(ScriptKind.TimelockRehearsal);
        assertEq(uint256(d.kind), uint256(ScriptKind.TimelockRehearsal));
        assertEq(d.namespace, 0);
        assertEq(d.id, 0);
        assertEq(d.prerequisites.length, 0);
        assertFalse(d.history);
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

    function testPrerequisitesResolveEachWriter() external pure {
        MigrationPrerequisite[] memory declared = new MigrationPrerequisite[](2);
        declared[0] = MigrationPrerequisite({writer: MigrationWriter.Timelock, namespace: "a", migration: "b"});
        declared[1] = MigrationPrerequisite({writer: MigrationWriter.Safe, namespace: "c", migration: "d"});
        ScriptDeclaration memory d = LibStoxMigrations.safeMigrationOnto("a", "e", "b", false);
        d.prerequisites = declared;
        Prerequisite[] memory resolved = LibStoxMigrations.prerequisitesFor(d, address(1), address(2));
        assertEq(resolved.length, 2);
        assertEq(resolved[0].writer, address(2));
        assertEq(resolved[0].namespace, "a");
        assertEq(resolved[0].migration, "b");
        assertEq(resolved[1].writer, address(1));
        assertEq(resolved[1].namespace, "c");
        assertEq(resolved[1].migration, "d");
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            resolved = LibStoxMigrations.prerequisitesForChainId(d, nets[i].chainId);
            assertEq(resolved[0].writer, LibTimelockInvariants.timelockForChainId(nets[i].chainId));
            assertEq(resolved[1].writer, LibSafeInvariants.safeForChainId(nets[i].chainId));
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
        (string[] memory paths, ScriptDeclaration[] memory declarations, address[] memory instances) =
            new BuildMigrations().discover("script");
        uint256 recorded = 0;
        for (uint256 i = 0; i < declarations.length; i++) {
            ScriptDeclaration memory d = declarations[i];
            if (d.kind != ScriptKind.Migration) continue;
            recorded++;
            string memory label = string.concat(network, ": ", paths[i]);
            address writer = LibStoxMigrations.writerForChainId(d.writer, block.chainid);
            Prerequisite[] memory declared = LibStoxMigrations.prerequisitesForChainId(d, block.chainid);
            uint256 moment = d.history ? IStoxHistoryMigration(instances[i]).executedAt(block.chainid) : 0;
            uint256 hits = 0;
            for (uint256 w = 0; w < writes.length; w++) {
                if (writes[w].namespace != d.namespace || writes[w].migration != d.id) continue;
                hits++;
                assertEq(writes[w].writer, writer, label);
                assertEq(writes[w].appliedAt, moment, label);
                assertPrerequisites(writes[w].prerequisites, declared, label);
            }
            assertEq(hits, 1, label);
            if (LibMigrationRegistry.applied(writer, d.namespace, d.id) != 0) {
                assertPrerequisites(LibMigrationRegistry.appliedAfter(writer, d.namespace, d.id), declared, label);
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
