// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import "../../script/AllScripts.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IMigrationRegistryV2, Prerequisite} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.18/src/lib/LibSafeTx.sol";

import {BuildMigrations} from "../../../script/BuildMigrations.sol";
import {migrateGovernanceToTimelockDeclaration} from "../../../script/20260729-migrate-governance-to-timelock.s.sol";
import {retireDirectSignerRolesDeclaration} from "../../../script/20260831-retire-direct-signer-roles.s.sol";
import {grantEuAuthoriserRolesDeclaration} from "../../../script/20261006-grant-eu-authoriser-roles.s.sol";
import {grantOrchestratorEmergencyDeclaration} from "../../../script/20261006-grant-orchestrator-emergency.s.sol";
import {orchestratorAdminToTimelockDeclaration} from "../../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {GrantEuAuthoriserRoles} from "../../../script/20261006-grant-eu-authoriser-roles.s.sol";
import {
    IStoxHistoryMigration,
    MigrationPrerequisite,
    MigrationWriter,
    ScriptDeclaration
} from "../../../src/interface/IStoxScript.sol";
import {LibEuAuthoriserClone} from "../../../src/lib/LibEuAuthoriserClone.sol";
import {LibRbacMigration} from "../../../src/lib/LibRbacMigration.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {GrantOrchestratorEmergencyHarness} from "../../script/GrantOrchestratorEmergencyHarness.sol";
import {BackfillHistoryHarness} from "../../script/BackfillHistoryHarness.sol";
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
        ScriptDeclaration memory declared = LibStoxMigrations.safeMigrationOnto("ns", "id", "head", true);
        assertTrue(declared.migration);
        assertEq(declared.namespace, "ns");
        assertEq(declared.id, "id");
        assertEq(uint256(declared.writer), uint256(MigrationWriter.Safe));
        assertTrue(declared.history);
        assertEq(declared.prerequisites.length, 1);
        assertEq(uint256(declared.prerequisites[0].writer), uint256(MigrationWriter.Safe));
        assertEq(declared.prerequisites[0].namespace, "ns");
        assertEq(declared.prerequisites[0].migration, "head");
        assertFalse(LibStoxMigrations.safeMigrationOnto("ns", "id", "head", false).history);
    }

    function testNotAMigrationCarriesNoRecord() external pure {
        ScriptDeclaration memory declared = LibStoxMigrations.notAMigration();
        assertFalse(declared.migration);
        assertEq(declared.namespace, 0);
        assertEq(declared.id, 0);
        assertEq(declared.prerequisites.length, 0);
        assertFalse(declared.history);
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
        ScriptDeclaration memory migration = LibStoxMigrations.safeMigrationOnto("a", "e", "b", false);
        migration.prerequisites = declared;
        Prerequisite[] memory resolved = LibStoxMigrations.prerequisitesFor(migration, address(1), address(2));
        assertEq(resolved.length, 2);
        assertEq(resolved[0].writer, address(2));
        assertEq(resolved[0].namespace, "a");
        assertEq(resolved[0].migration, "b");
        assertEq(resolved[1].writer, address(1));
        assertEq(resolved[1].namespace, "c");
        assertEq(resolved[1].migration, "d");
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            resolved = LibStoxMigrations.prerequisitesForChainId(migration, nets[i].chainId);
            assertEq(resolved[0].writer, LibTimelockInvariants.timelockForChainId(nets[i].chainId));
            assertEq(resolved[1].writer, LibSafeInvariants.safeForChainId(nets[i].chainId));
        }
    }

    /// @dev Invariants read these records by the library constants, so each
    /// script's declaration must be keyed by the same one.
    function testDeclarationsAreKeyedByTheConstantsTheInvariantsRead() external pure {
        assertEq(migrateGovernanceToTimelockDeclaration().id, LibStoxMigrations.GOVERNANCE_TIMELOCK);
        assertEq(grantOrchestratorEmergencyDeclaration().id, LibStoxMigrations.ORCHESTRATOR_EMERGENCY);
        assertEq(orchestratorAdminToTimelockDeclaration().id, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        assertEq(grantEuAuthoriserRolesDeclaration().id, LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER);
        assertEq(grantEuAuthoriserRolesDeclaration().namespace, LibRbacMigration.STOX_RBAC_NAMESPACE);
        assertEq(retireDirectSignerRolesDeclaration().id, LibRbacMigration.SERVICE_SIGNER_DIRECT_ROLES_RETIRED);
        assertEq(retireDirectSignerRolesDeclaration().namespace, LibRbacMigration.STOX_RBAC_NAMESPACE);
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

    function decodeSchedule(bytes calldata data)
        external
        pure
        returns (address[] memory targets, bytes[] memory payloads)
    {
        assertEq(bytes4(data[:4]), TimelockController.scheduleBatch.selector);
        (targets,, payloads,,,) = abi.decode(data[4:], (address[], uint256[], bytes[], bytes32, bytes32, uint256));
    }

    /// @dev Every registry call in the bundles that write this repo's records:
    /// the Safe's own calls, and the calls inside a batch the Safe schedules
    /// on the timelock, which the timelock makes.
    function bundleWrites(string memory network) internal returns (RegistryWrite[] memory) {
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        SafeTx[][4] memory bundles = [
            new GrantOrchestratorEmergencyHarness(network).callAuthorBundle(),
            new OrchestratorAdminToTimelockHarness(network).callAuthorBundle(),
            new BackfillHistoryHarness(network).callAuthorBundle(),
            new GrantEuAuthoriserRoles()
                .grantBundle(LibEuAuthoriserClone.cloneDeployedAddress(block.chainid), safe, timelock)
        ];
        RegistryWrite[] memory writes = new RegistryWrite[](32);
        uint256 writeCount = 0;
        address registry = LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS;
        for (uint256 bundleIndex = 0; bundleIndex < bundles.length; bundleIndex++) {
            for (uint256 txIndex = 0; txIndex < bundles[bundleIndex].length; txIndex++) {
                if (bundles[bundleIndex][txIndex].to == registry) {
                    writes[writeCount] = this.decodeWrite(bundles[bundleIndex][txIndex].data);
                    writes[writeCount++].writer = safe;
                } else if (bundles[bundleIndex][txIndex].to == timelock) {
                    (address[] memory targets, bytes[] memory payloads) =
                        this.decodeSchedule(bundles[bundleIndex][txIndex].data);
                    for (uint256 callIndex = 0; callIndex < targets.length; callIndex++) {
                        if (targets[callIndex] != registry) continue;
                        writes[writeCount] = this.decodeWrite(payloads[callIndex]);
                        writes[writeCount++].writer = timelock;
                    }
                }
            }
        }
        assembly ("memory-safe") {
            mstore(writes, writeCount)
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

    /// @dev Declared migrations whose bundles do not write their records yet.
    /// Each one's fix deletes its entry here.
    function unrecorded(string memory path) internal pure returns (bool) {
        bytes32 key = keccak256(bytes(path));
        return key == keccak256("script/20260619-migrate-multisig-threshold.s.sol")
            || key == keccak256("script/20260831-retire-direct-signer-roles.s.sol");
    }

    function assertRecordsAreTheBundles(string memory network) internal {
        vm.createSelectFork(network);
        RegistryWrite[] memory writes = bundleWrites(network);
        (string[] memory paths, ScriptDeclaration[] memory declarations, address[] memory instances) =
            new BuildMigrations().discover("script");
        uint256 recorded = 0;
        for (uint256 i = 0; i < declarations.length; i++) {
            ScriptDeclaration memory declared = declarations[i];
            if (!declared.migration) continue;
            string memory label = string.concat(network, ": ", paths[i]);
            if (unrecorded(paths[i])) {
                for (uint256 writeIndex = 0; writeIndex < writes.length; writeIndex++) {
                    assertTrue(
                        writes[writeIndex].namespace != declared.namespace
                            || writes[writeIndex].migration != declared.id,
                        label
                    );
                }
                continue;
            }
            recorded++;
            address writer = LibStoxMigrations.writerForChainId(declared.writer, block.chainid);
            Prerequisite[] memory expected = LibStoxMigrations.prerequisitesForChainId(declared, block.chainid);
            uint256 moment = declared.history ? IStoxHistoryMigration(instances[i]).executedAt(block.chainid) : 0;
            uint256 hits = 0;
            for (uint256 writeIndex = 0; writeIndex < writes.length; writeIndex++) {
                if (writes[writeIndex].namespace != declared.namespace || writes[writeIndex].migration != declared.id) {
                    continue;
                }
                hits++;
                assertEq(writes[writeIndex].writer, writer, label);
                assertEq(writes[writeIndex].appliedAt, moment, label);
                assertPrerequisites(writes[writeIndex].prerequisites, expected, label);
            }
            assertEq(hits, 1, label);
            if (LibMigrationRegistry.applied(writer, declared.namespace, declared.id) != 0) {
                assertPrerequisites(
                    LibMigrationRegistry.appliedAfter(writer, declared.namespace, declared.id), expected, label
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
