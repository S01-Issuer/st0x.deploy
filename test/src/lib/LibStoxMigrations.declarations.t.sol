// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import "../../script/AllScripts.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IMigrationRegistryV3, Prerequisite} from "rain-deploy-0.1.21/src/interface/IMigrationRegistryV3.sol";
import {IMigrationRegistryV2} from "rain-deploy-0.1.21/src/interface/deprecated/IMigrationRegistryV2.sol";
import {DEPLOYED_ADDRESS as REGISTRY_V2} from "rain-deploy-0.1.21/src/generated/0_1_18/MigrationRegistry.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.21/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.21/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.21/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.21/src/lib/LibSafeTx.sol";

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
import {BackfillMigrationRegistryV3Harness} from "../../script/BackfillMigrationRegistryV3Harness.sol";
import {backfillMigrationRegistryV3Declaration} from "../../../script/20261022-backfill-migration-registry-v3.s.sol";
import {OrchestratorAdminToTimelockHarness} from "../../script/OrchestratorAdminToTimelockHarness.sol";
import {BootstrapMintCapsOrchestratorHarness} from "../../script/BootstrapMintCapsOrchestratorHarness.sol";
import {Float} from "rain-math-float-0.3.10/src/lib/LibDecimalFloat.sol";
import {EvaluableV4} from "rainlang-interface-0.2.13/src/interface/IInterpreterCallerV4.sol";
import {IInterpreterV4} from "rainlang-interface-0.2.13/src/interface/IInterpreterV4.sol";
import {IInterpreterStoreV3} from "rainlang-interface-0.2.13/src/interface/IInterpreterStoreV3.sol";

struct RegistryWrite {
    address writer;
    bytes32 namespace;
    bytes32 migration;
    uint256 appliedAt;
    Prerequisite[] prerequisites;
    bool copy;
}

/// @title LibStoxMigrationsDeclarationsTest
/// @notice The declaration helpers resolve roles to each chain's Safe and
/// timelock, and every migration a script declares is written by exactly one
/// bundle, with the writer, prerequisites and moment it declares, and the V3
/// backfill copies every V2 record at its V2 moment.
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
        if (selector == IMigrationRegistryV3.applyMigrationV3.selector) {
            (write.writer, write.namespace, write.migration, write.prerequisites) =
                abi.decode(data[4:], (address, bytes32, bytes32, Prerequisite[]));
        } else {
            assertEq(selector, IMigrationRegistryV3.applyMigrationHistoryV3.selector);
            (write.writer, write.namespace, write.migration, write.appliedAt, write.prerequisites) =
                abi.decode(data[4:], (address, bytes32, bytes32, uint256, Prerequisite[]));
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

    function bootstrapBundle() internal returns (SafeTx[] memory) {
        BootstrapMintCapsOrchestratorHarness bootstrap = new BootstrapMintCapsOrchestratorHarness();
        bootstrap.configure(
            EvaluableV4({
                interpreter: IInterpreterV4(address(0x1)), store: IInterpreterStoreV3(address(0x2)), bytecode: hex"00"
            }),
            address(0xA11CE),
            address(0xB0B),
            Float.wrap(0),
            Float.wrap(0)
        );
        return bootstrap.callAuthorBundle();
    }

    /// @dev Every registry call in the bundles that write this repo's records:
    /// the Safe's own calls, and the calls inside a batch the Safe schedules
    /// on the timelock, which the timelock makes. Each names its sender as the
    /// writer. The V3 backfill's writes other than its own record are copies
    /// of V2 history.
    function bundleWrites(string memory network) internal returns (RegistryWrite[] memory) {
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        SafeTx[][6] memory bundles = [
            new GrantOrchestratorEmergencyHarness(network).callAuthorBundle(),
            new OrchestratorAdminToTimelockHarness(network).callAuthorBundle(),
            new BackfillHistoryHarness(network).callAuthorBundle(),
            new GrantEuAuthoriserRoles()
                .grantBundle(LibEuAuthoriserClone.cloneDeployedAddress(block.chainid), safe, timelock),
            new BackfillMigrationRegistryV3Harness(network).callAuthorBundle(),
            bootstrapBundle()
        ];
        RegistryWrite[] memory writes = new RegistryWrite[](32);
        uint256 writeCount = 0;
        for (uint256 bundleIndex = 0; bundleIndex < bundles.length; bundleIndex++) {
            writeCount = collectWrites(bundles[bundleIndex], bundleIndex == 4, writes, writeCount, network);
        }
        assembly ("memory-safe") {
            mstore(writes, writeCount)
        }
        return writes;
    }

    /// @dev Appends `bundle`'s registry writes to `writes` from `writeCount`
    /// and returns the new count.
    function collectWrites(
        SafeTx[] memory bundle,
        bool backfillV3,
        RegistryWrite[] memory writes,
        uint256 writeCount,
        string memory network
    ) internal view returns (uint256) {
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address registry = LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS;
        for (uint256 txIndex = 0; txIndex < bundle.length; txIndex++) {
            if (bundle[txIndex].to == registry) {
                writes[writeCount] = this.decodeWrite(bundle[txIndex].data);
                assertEq(writes[writeCount].writer, LibSafeInvariants.safeForChainId(block.chainid), network);
                writes[writeCount].copy =
                    backfillV3 && writes[writeCount].migration != backfillMigrationRegistryV3Declaration().id;
                writeCount++;
            } else if (bundle[txIndex].to == timelock) {
                (address[] memory targets, bytes[] memory payloads) = this.decodeSchedule(bundle[txIndex].data);
                for (uint256 callIndex = 0; callIndex < targets.length; callIndex++) {
                    if (targets[callIndex] != registry) continue;
                    writes[writeCount] = this.decodeWrite(payloads[callIndex]);
                    assertEq(writes[writeCount++].writer, timelock, network);
                }
            }
        }
        return writeCount;
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
        uint256 copied = 0;
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
            copied += assertDeclaredWrites(writes, declared, instances[i], label);
        }
        assertEq(writes.length, recorded + copied, network);
    }

    /// @dev `declared` is written once as declared, plus one copy at its V2
    /// moment when V2 holds it. Returns the number of copies.
    function assertDeclaredWrites(
        RegistryWrite[] memory writes,
        ScriptDeclaration memory declared,
        address instance,
        string memory label
    ) internal view returns (uint256) {
        address writer = LibStoxMigrations.writerForChainId(declared.writer, block.chainid);
        Prerequisite[] memory expected = LibStoxMigrations.prerequisitesForChainId(declared, block.chainid);
        uint256 moment = declared.history ? IStoxHistoryMigration(instance).executedAt(block.chainid) : 0;
        uint256 v2Moment = IMigrationRegistryV2(REGISTRY_V2).applied(writer, declared.namespace, declared.id);
        uint256 hits = 0;
        uint256 copies = 0;
        for (uint256 writeIndex = 0; writeIndex < writes.length; writeIndex++) {
            if (writes[writeIndex].namespace != declared.namespace || writes[writeIndex].migration != declared.id) {
                continue;
            }
            assertEq(writes[writeIndex].writer, writer, label);
            assertPrerequisites(writes[writeIndex].prerequisites, expected, label);
            if (writes[writeIndex].copy) {
                copies++;
                assertEq(writes[writeIndex].appliedAt, v2Moment, label);
            } else {
                hits++;
                assertEq(writes[writeIndex].appliedAt, moment, label);
            }
        }
        assertEq(hits, 1, label);
        assertEq(copies, v2Moment == 0 ? 0 : 1, label);
        if (LibMigrationRegistry.appliedV3(writer, declared.namespace, declared.id) != 0) {
            assertPrerequisites(
                LibMigrationRegistry.appliedAfterV3(writer, declared.namespace, declared.id), expected, label
            );
        }
        return copies;
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
