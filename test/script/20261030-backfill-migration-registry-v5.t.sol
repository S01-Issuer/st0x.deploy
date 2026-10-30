// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV3} from "rain-deploy-0.1.29/src/interface/deprecated/IMigrationRegistryV3.sol";
import {DEPLOYED_ADDRESS as REGISTRY_V3} from "rain-deploy-0.1.29/src/generated/0_1_25/MigrationRegistry.sol";
import {IMigrationRegistryV5} from "rain-deploy-0.1.29/src/interface/IMigrationRegistryV5.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.29/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.29/src/lib/LibMigrationRegistryDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.29/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.29/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.29/src/lib/LibSafeTxBuilderJson.sol";

import {
    BackfillV5RecordMismatch,
    BackfillV5RecordMissing,
    backfillMigrationRegistryV5Declaration
} from "../../script/20261030-backfill-migration-registry-v5.s.sol";
import {backfillMigrationRegistryV3Declaration} from "../../script/20261022-backfill-migration-registry-v3.s.sol";
import {grantEuAuthoriserRolesDeclaration} from "../../script/20261006-grant-eu-authoriser-roles.s.sol";
import {grantOrchestratorEmergencyDeclaration} from "../../script/20261006-grant-orchestrator-emergency.s.sol";
import {migrateGovernanceToTimelockDeclaration} from "../../script/20260729-migrate-governance-to-timelock.s.sol";
import {migrateMultisigThresholdDeclaration} from "../../script/20260619-migrate-multisig-threshold.s.sol";
import {orchestratorAdminToTimelockDeclaration} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {BackfillMigrationRegistryV3Harness} from "./BackfillMigrationRegistryV3Harness.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibRbacMigration} from "../../src/lib/LibRbacMigration.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title BackfillMigrationRegistryV5Test
/// @notice Per network, with the V3 backfill landed (live, or its bundle on the
/// fork): the bundle carries every V3 record of the Safe onto V5 at its V3
/// moment, from its own declaration, and re-authoring after it is empty.
contract BackfillMigrationRegistryV5Test is Test {
    IMigrationRegistryV3 internal constant V3 = IMigrationRegistryV3(REGISTRY_V3);

    function safeLines() internal pure returns (ScriptDeclaration[][] memory) {
        ScriptDeclaration[][] memory all = new ScriptDeclaration[][](2);
        all[0] = new ScriptDeclaration[](5);
        all[0][0] = migrateGovernanceToTimelockDeclaration();
        all[0][1] = grantOrchestratorEmergencyDeclaration();
        all[0][2] = backfillMigrationRegistryV3Declaration();
        all[0][3] = orchestratorAdminToTimelockDeclaration();
        all[0][4] = migrateMultisigThresholdDeclaration();
        all[1] = new ScriptDeclaration[](1);
        all[1][0] = grantEuAuthoriserRolesDeclaration();
        return all;
    }

    function v5Moment(address safe, ScriptDeclaration memory declared) internal view returns (uint256) {
        return LibMigrationRegistry.appliedV5(safe, declared.namespace, declared.id);
    }

    function forkWithV3Backfill(string memory network) internal returns (address) {
        vm.createSelectFork(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        if (V3.appliedV3(safe, LibStoxMigrations.NAMESPACE, backfillMigrationRegistryV3Declaration().id) == 0) {
            BackfillMigrationRegistryV3Harness v3 = new BackfillMigrationRegistryV3Harness(string.concat("v5-", network));
            LibSafeFork.executeBundle(vm, Safe(payable(safe)), v3.callAuthorBundle());
        }
        return safe;
    }

    function assertCarried(address safe) internal view {
        ScriptDeclaration[][] memory all = safeLines();
        for (uint256 i = 0; i < all.length; i++) {
            for (uint256 j = 0; j < all[i].length; j++) {
                ScriptDeclaration memory declared = all[i][j];
                uint256 v3At = V3.appliedV3(safe, declared.namespace, declared.id);
                if (v3At == 0) break;
                assertEq(v5Moment(safe, declared), v3At, "V5 moment is the V3 moment");
                assertEq(
                    LibMigrationRegistry.appliedOntoV5(safe, declared.namespace, declared.id),
                    declared.prerequisites[0].migration,
                    "V5 record is onto its declared head"
                );
                assertEq(
                    LibMigrationRegistry.appliedByV5(safe, declared.namespace, declared.id), safe, "written by the Safe"
                );
            }
        }
        assertTrue(v5Moment(safe, backfillMigrationRegistryV3Declaration()) != 0, "V3 backfill record carried");
        assertEq(
            LibMigrationRegistry.headV5(safe, LibRbacMigration.STOX_RBAC_NAMESPACE),
            LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER,
            "rbac line carried"
        );
    }

    function assertBundle(string memory network) internal {
        address safe = forkWithV3Backfill(network);
        BackfillMigrationRegistryV5Harness script = new BackfillMigrationRegistryV5Harness(network);

        if (v5Moment(safe, backfillMigrationRegistryV3Declaration()) != 0) {
            console2.log(string.concat("EXECUTED [", network, "]: asserting the carried state"));
            assertCarried(safe);
            script.callAssertPostState();
            return;
        }

        console2.log(string.concat("PENDING [", network, "]: authoring, verifying and executing the bundle"));
        uint256 preRun = vm.snapshotState();
        script.run();
        vm.revertToState(preRun);

        string memory artifactPath = script.callArtifactPath();
        script.verify(artifactPath);

        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, safe, "artifact Safe");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        assertCarried(safe);
        assertEq(
            LibStoxMigrations.head(safe), backfillMigrationRegistryV3Declaration().id, "deploy line at V3's head"
        );
        assertEq(script.callAuthorBundle().length, 0, "re-authoring after execution is empty");
        script.callAssertPostState();
    }

    function testBackfillBundleBase() external {
        assertBundle(LibRainDeploy.BASE);
    }

    function testBackfillBundleEthereum() external {
        assertBundle(LibStoxDeployNetworks.ETHEREUM);
    }

    function testBackfillBundleHyperEvm() external {
        assertBundle(LibStoxDeployNetworks.HYPEREVM);
    }

    function testBackfillBundleRobinhood() external {
        assertBundle(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testBackfillBundleBsc() external {
        assertBundle(LibStoxDeployNetworks.BSC);
    }

    /// @notice The refusal and shape tests need V5 before the backfill.
    function setUpBase() internal returns (BackfillMigrationRegistryV5Harness, address, bool) {
        address safe = forkWithV3Backfill(LibRainDeploy.BASE);
        BackfillMigrationRegistryV5Harness script = new BackfillMigrationRegistryV5Harness("shape");
        if (v5Moment(safe, backfillMigrationRegistryV3Declaration()) != 0) {
            console2.log("SPENT: the V5 backfill has executed on this chain");
            return (script, safe, true);
        }
        return (script, safe, false);
    }

    function mockV3Moment(address safe, ScriptDeclaration memory declared, uint256 at) internal {
        vm.mockCall(
            REGISTRY_V3,
            abi.encodeCall(IMigrationRegistryV3.appliedV3, (safe, declared.namespace, declared.id)),
            abi.encode(at)
        );
    }

    function testBundleSkipsRecordsV5AlreadyHolds() external {
        (BackfillMigrationRegistryV5Harness script, address safe, bool spent) = setUpBase();
        if (spent) return;
        uint256 full = script.callAuthorBundle().length;
        ScriptDeclaration memory governance = migrateGovernanceToTimelockDeclaration();
        (address to, bytes memory data) = LibStoxMigrations.historyCall(
            governance,
            V3.appliedV3(safe, governance.namespace, governance.id),
            safe,
            LibTimelockInvariants.timelockForChainId(block.chainid)
        );
        vm.prank(safe);
        (bool ok,) = to.call(data);
        assertTrue(ok, "governance record written");
        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, full - 1);
        for (uint256 i = 0; i < txs.length; i++) {
            assertTrue(keccak256(txs[i].data) != keccak256(data), "held record replayed");
        }
    }

    function testRecordV3LacksEndsItsLine() external {
        (BackfillMigrationRegistryV5Harness script, address safe, bool spent) = setUpBase();
        if (spent) return;
        mockV3Moment(safe, grantOrchestratorEmergencyDeclaration(), 0);
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        assertTrue(v5Moment(safe, migrateGovernanceToTimelockDeclaration()) != 0, "governance carried");
        assertEq(v5Moment(safe, grantOrchestratorEmergencyDeclaration()), 0, "a record V3 lacks is not replayed");
        assertEq(v5Moment(safe, backfillMigrationRegistryV3Declaration()), 0, "the line ends at the gap");
        assertTrue(v5Moment(safe, grantEuAuthoriserRolesDeclaration()) != 0, "the rbac line replays on its own");
    }

    function testBundleEndsWithOwnRecordOnceItsPredecessorHeadsTheLine() external {
        (BackfillMigrationRegistryV5Harness script, address safe, bool spent) = setUpBase();
        if (spent) return;
        mockV3Moment(safe, orchestratorAdminToTimelockDeclaration(), block.timestamp);
        mockV3Moment(safe, migrateMultisigThresholdDeclaration(), block.timestamp);
        ScriptDeclaration memory own = backfillMigrationRegistryV5Declaration();
        (address to, bytes memory data) =
            LibStoxMigrations.recordCall(own, safe, LibTimelockInvariants.timelockForChainId(block.chainid));
        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs[txs.length - 1].to, to);
        assertEq(txs[txs.length - 1].data, data);

        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);
        assertEq(LibStoxMigrations.applied(safe, own.id), block.timestamp, "own record moment");
        assertEq(LibStoxMigrations.head(safe), own.id);
        assertEq(
            LibMigrationRegistry.appliedOntoV5(safe, own.namespace, own.id), migrateMultisigThresholdDeclaration().id
        );
        script.callAssertPostState();
    }

    function testBundleOmitsOwnRecordWhileItsPredecessorIsMissing() external {
        (BackfillMigrationRegistryV5Harness script, address safe, bool spent) = setUpBase();
        if (spent) return;
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        assertEq(LibStoxMigrations.applied(safe, backfillMigrationRegistryV5Declaration().id), 0);
        script.callAssertPostState();
    }

    function testPostStateRefusesAMomentOtherThanV3s() external {
        (BackfillMigrationRegistryV5Harness script, address safe, bool spent) = setUpBase();
        if (spent) return;
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        ScriptDeclaration memory governance = migrateGovernanceToTimelockDeclaration();
        uint256 v5At = v5Moment(safe, governance);
        mockV3Moment(safe, governance, v5At + 1);
        vm.expectRevert(abi.encodeWithSelector(BackfillV5RecordMismatch.selector, governance.id, v5At + 1, v5At));
        script.callAssertPostState();
    }

    function testPostStateRefusesAMissingOwnRecordAfterItsPredecessor() external {
        (BackfillMigrationRegistryV5Harness script, address safe, bool spent) = setUpBase();
        if (spent) return;
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        ScriptDeclaration memory own = backfillMigrationRegistryV5Declaration();
        vm.mockCall(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            abi.encodeCall(IMigrationRegistryV5.appliedV5, (safe, own.namespace, own.prerequisites[0].migration)),
            abi.encode(block.timestamp)
        );
        vm.expectRevert(abi.encodeWithSelector(BackfillV5RecordMissing.selector, own.id));
        script.callAssertPostState();
    }
}
