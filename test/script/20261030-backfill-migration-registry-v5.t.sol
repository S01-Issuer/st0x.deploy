// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibRainDeploy} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV2} from "rain-deploy-0.1.29/src/interface/deprecated/IMigrationRegistryV2.sol";
import {DEPLOYED_ADDRESS as REGISTRY_V2} from "rain-deploy-0.1.29/src/generated/0_1_18/MigrationRegistry.sol";
import {IMigrationRegistryV5, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.29/src/interface/IMigrationRegistryV5.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.29/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.29/src/lib/LibMigrationRegistryDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.29/src/lib/LibSafeTx.sol";
import {LibSafe} from "rain-deploy-0.1.29/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.29/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.29/src/lib/LibSafeTxBuilderJson.sol";
import {ITimelockControllerState, LibTimelockController} from "rain-deploy-0.1.29/src/lib/LibTimelockController.sol";

import {
    BackfillV5OrderMismatch,
    BackfillV5RecordMismatch,
    BackfillV5RecordMissing,
    GovernanceTimelockMomentMismatch,
    UnexpectedRegistryV2CodeHash,
    UnexpectedRegistryV2Line,
    UnexpectedRegistryV2Order,
    backfillMigrationRegistryV5Declaration
} from "../../script/20261030-backfill-migration-registry-v5.s.sol";
import {grantEuAuthoriserRolesDeclaration} from "../../script/20261006-grant-eu-authoriser-roles.s.sol";
import {grantOrchestratorEmergencyDeclaration} from "../../script/20261006-grant-orchestrator-emergency.s.sol";
import {migrateGovernanceToTimelockDeclaration} from "../../script/20260729-migrate-governance-to-timelock.s.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibRbacMigration} from "../../src/lib/LibRbacMigration.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title BackfillMigrationRegistryV5Test
/// @notice Per network: the bundle replays the Safe's V2 records onto V5 at
/// their V2 moments and onto their V2 predecessors, skips what V5 holds, and
/// ends with its own record onto `ORCHESTRATOR_EMERGENCY`; the script refuses
/// a V2 state other than the one it carries over.
contract BackfillMigrationRegistryV5Test is Test {
    IMigrationRegistryV2 internal constant V2 = IMigrationRegistryV2(REGISTRY_V2);
    IMigrationRegistryV5 internal constant V5 =
        IMigrationRegistryV5(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);

    function v2Records() internal pure returns (ScriptDeclaration[] memory) {
        ScriptDeclaration[] memory all = new ScriptDeclaration[](3);
        all[0] = migrateGovernanceToTimelockDeclaration();
        all[1] = grantOrchestratorEmergencyDeclaration();
        all[2] = grantEuAuthoriserRolesDeclaration();
        return all;
    }

    function v2Moment(address safe, ScriptDeclaration memory declared) internal view returns (uint256) {
        return V2.applied(safe, declared.namespace, declared.id);
    }

    function v5Moment(address safe, ScriptDeclaration memory declared) internal view returns (uint256) {
        return LibMigrationRegistry.appliedV5(safe, declared.namespace, declared.id);
    }

    function historyData(address safe, bytes32 namespace, bytes32 id, uint256 at, bytes32 onto)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(
            IMigrationRegistryV5.applyMigrationHistoryV5,
            (safe, namespace, id, at, LibMigrationRegistry.onto(safe, namespace, onto), "")
        );
    }

    function ownData(address safe) internal pure returns (bytes memory) {
        return abi.encodeCall(
            IMigrationRegistryV5.applyMigrationV5,
            (
                safe,
                LibStoxMigrations.NAMESPACE,
                LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5,
                LibMigrationRegistry.onto(safe, LibStoxMigrations.NAMESPACE, LibStoxMigrations.ORCHESTRATOR_EMERGENCY),
                ""
            )
        );
    }

    function holdOnV5(address safe, ScriptDeclaration memory declared, uint256 at) internal {
        holdOnV5Onto(safe, declared.namespace, declared.id, at, declared.prerequisites[0].migration);
    }

    function holdOnV5Onto(address safe, bytes32 namespace, bytes32 migration, uint256 at, bytes32 onto) internal {
        vm.prank(safe);
        V5.applyMigrationHistoryV5(safe, namespace, migration, at, LibMigrationRegistry.onto(safe, namespace, onto), "");
    }

    function assertReplayed(address safe) internal view {
        ScriptDeclaration[] memory all = v2Records();
        for (uint256 i = 0; i < all.length; i++) {
            ScriptDeclaration memory declared = all[i];
            uint256 v2At = v2Moment(safe, declared);
            assertTrue(v2At != 0, "V2 holds the record");
            assertEq(v5Moment(safe, declared), v2At, "V5 moment is the V2 moment");
            assertEq(
                LibMigrationRegistry.appliedOntoV5(safe, declared.namespace, declared.id),
                V2.appliedOnto(safe, declared.namespace, declared.id),
                "V5 predecessor is the V2 predecessor"
            );
            assertEq(
                LibMigrationRegistry.appliedByV5(safe, declared.namespace, declared.id), safe, "written by the Safe"
            );
        }
        bytes32 own = LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5;
        assertTrue(LibStoxMigrations.applied(safe, own) != 0, "own record");
        assertEq(
            LibMigrationRegistry.appliedOntoV5(safe, LibStoxMigrations.NAMESPACE, own),
            LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
            "own record onto the V2 deploy-line tail"
        );
        assertEq(LibMigrationRegistry.appliedByV5(safe, LibStoxMigrations.NAMESPACE, own), safe, "own record by Safe");
    }

    function assertBackfill(string memory network) internal {
        vm.createSelectFork(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        BackfillMigrationRegistryV5Harness script = new BackfillMigrationRegistryV5Harness(network);

        if (LibStoxMigrations.applied(safe, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5) != 0) {
            console2.log(string.concat("EXECUTED [", network, "]: asserting the replayed state"));
            assertReplayed(safe);
            assertEq(script.callAuthorBundle().length, 0, "nothing left to replay");
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

        assertReplayed(safe);
        assertEq(
            LibStoxMigrations.applied(safe, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5),
            block.timestamp,
            "own record moment"
        );
        assertEq(LibStoxMigrations.head(safe), LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5, "deploy line head");
        assertEq(
            LibMigrationRegistry.headV5(safe, LibRbacMigration.STOX_RBAC_NAMESPACE),
            LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER,
            "rbac line head"
        );
        assertEq(script.callAuthorBundle().length, 0, "re-authoring after execution is empty");
        script.callAssertPostState();
    }

    function testBackfillBundleBase() external {
        assertBackfill(LibRainDeploy.BASE);
    }

    function testBackfillBundleEthereum() external {
        assertBackfill(LibStoxDeployNetworks.ETHEREUM);
    }

    function testBackfillBundleHyperEvm() external {
        assertBackfill(LibStoxDeployNetworks.HYPEREVM);
    }

    function testBackfillBundleRobinhood() external {
        assertBackfill(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testBackfillBundleBsc() external {
        assertBackfill(LibStoxDeployNetworks.BSC);
    }

    function setUpBase() internal returns (BackfillMigrationRegistryV5Harness, address) {
        vm.createSelectFork(LibRainDeploy.BASE);
        return (new BackfillMigrationRegistryV5Harness("refusal"), LibSafeInvariants.safeForChainId(block.chainid));
    }

    /// @notice The bundle and post-state tests need V5 before the backfill.
    function spent(address safe) internal view returns (bool) {
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5) != 0) {
            console2.log("SPENT: the V5 backfill has executed on this chain");
            return true;
        }
        return false;
    }

    function testBundleIsTheV2RecordsInLineOrderThenOwnRecord() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent(safe)) return;
        bytes32 ns = LibStoxMigrations.NAMESPACE;
        bytes32 rbac = LibRbacMigration.STOX_RBAC_NAMESPACE;
        bytes32 gov = LibStoxMigrations.GOVERNANCE_TIMELOCK;
        bytes32 emergency = LibStoxMigrations.ORCHESTRATOR_EMERGENCY;
        bytes32 eu = LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER;
        bytes[] memory expected = new bytes[](4);
        expected[0] = historyData(safe, ns, gov, V2.applied(safe, ns, gov), MIGRATION_HEAD_GENESIS);
        expected[1] = historyData(safe, ns, emergency, V2.applied(safe, ns, emergency), gov);
        expected[2] = historyData(safe, rbac, eu, V2.applied(safe, rbac, eu), MIGRATION_HEAD_GENESIS);
        expected[3] = ownData(safe);

        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, expected.length, "bundle length");
        for (uint256 i = 0; i < txs.length; i++) {
            assertEq(txs[i].to, address(V5), "to the V5 registry");
            assertEq(txs[i].value, 0, "no value");
            assertEq(uint8(txs[i].operation), uint8(Enum.Operation.Call), "call");
            assertEq(txs[i].data, expected[i], "calldata");
        }
    }

    function testBundleSkipsRecordsV5Holds() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent(safe)) return;
        ScriptDeclaration memory gov = migrateGovernanceToTimelockDeclaration();
        ScriptDeclaration memory eu = grantEuAuthoriserRolesDeclaration();
        holdOnV5(safe, gov, v2Moment(safe, gov));
        holdOnV5(safe, eu, v2Moment(safe, eu));

        SafeTx[] memory txs = script.callAuthorBundle();
        ScriptDeclaration memory emergency = grantOrchestratorEmergencyDeclaration();
        assertEq(txs.length, 2, "only what V5 lacks");
        assertEq(
            txs[0].data,
            historyData(safe, emergency.namespace, emergency.id, v2Moment(safe, emergency), gov.id),
            "emergency replayed"
        );
        assertEq(txs[1].data, ownData(safe), "own record");

        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);
        assertReplayed(safe);
        script.callAssertPostState();
    }

    function testBundleIsOwnRecordOnceV5HoldsEveryV2Record() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent(safe)) return;
        ScriptDeclaration[] memory all = v2Records();
        for (uint256 i = 0; i < all.length; i++) {
            holdOnV5(safe, all[i], v2Moment(safe, all[i]));
        }
        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, 1, "own record only");
        assertEq(txs[0].data, ownData(safe), "own record");
    }

    function testSkippedRecordAtAnotherMomentFailsPostState() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent(safe)) return;
        ScriptDeclaration memory gov = migrateGovernanceToTimelockDeclaration();
        uint256 v2At = v2Moment(safe, gov);
        holdOnV5(safe, gov, v2At - 1);
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        vm.expectRevert(abi.encodeWithSelector(BackfillV5RecordMismatch.selector, gov.id, v2At, v2At - 1));
        script.callAssertPostState();
    }

    /// @dev V5 holds record `index` at its V2 moment, onto another record that
    /// sits where its V2 predecessor should.
    function assertSkippedRecordOntoAnotherPredecessorFailsPostState(uint256 index) internal {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent(safe)) return;
        ScriptDeclaration[] memory all = v2Records();
        ScriptDeclaration memory declared = all[index];
        for (uint256 i = 0; i < index; i++) {
            if (all[i].namespace == declared.namespace) holdOnV5(safe, all[i], v2Moment(safe, all[i]));
        }
        bytes32 other = keccak256("some other migration");
        uint256 v2At = v2Moment(safe, declared);
        holdOnV5Onto(safe, declared.namespace, other, v2At, declared.prerequisites[0].migration);
        holdOnV5Onto(safe, declared.namespace, declared.id, v2At, other);
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        assertEq(v5Moment(safe, declared), v2At, "V5 moment is the V2 moment");
        vm.expectRevert(abi.encodeWithSelector(BackfillV5OrderMismatch.selector, declared.id, other));
        script.callAssertPostState();
    }

    function testSkippedGovernanceTimelockOntoAnotherPredecessorFailsPostState() external {
        assertSkippedRecordOntoAnotherPredecessorFailsPostState(0);
    }

    function testSkippedOrchestratorEmergencyOntoAnotherPredecessorFailsPostState() external {
        assertSkippedRecordOntoAnotherPredecessorFailsPostState(1);
    }

    function testSkippedEuAuthoriserGrantOntoAnotherPredecessorFailsPostState() external {
        assertSkippedRecordOntoAnotherPredecessorFailsPostState(2);
    }

    function testOwnRecordOntoAnotherRecordFailsPostState() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent(safe)) return;
        ScriptDeclaration[] memory all = v2Records();
        for (uint256 i = 0; i < all.length; i++) {
            holdOnV5(safe, all[i], v2Moment(safe, all[i]));
        }
        bytes32 own = LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5;
        bytes32 other = keccak256("some other migration");
        holdOnV5Onto(
            safe, LibStoxMigrations.NAMESPACE, other, block.timestamp, LibStoxMigrations.ORCHESTRATOR_EMERGENCY
        );
        holdOnV5Onto(safe, LibStoxMigrations.NAMESPACE, own, block.timestamp, other);
        assertEq(script.callAuthorBundle().length, 0, "V5 holds every record");
        vm.expectRevert(abi.encodeWithSelector(BackfillV5OrderMismatch.selector, own, other));
        script.callAssertPostState();
    }

    function testRefusesUnpinnedRegistryV2Code() external {
        (BackfillMigrationRegistryV5Harness script,) = setUpBase();
        vm.etch(REGISTRY_V2, hex"00");
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRegistryV2CodeHash.selector, keccak256(hex"00")));
        script.callPreflight();
    }

    function testRefusesUnexpectedV2DeployHead() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        bytes32 other = keccak256("some other migration");
        vm.mockCall(
            REGISTRY_V2,
            abi.encodeCall(IMigrationRegistryV2.head, (safe, LibStoxMigrations.NAMESPACE)),
            abi.encode(other)
        );
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRegistryV2Line.selector, LibStoxMigrations.NAMESPACE, other));
        script.callPreflight();
    }

    function testRefusesUnexpectedV2RbacHead() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        bytes32 other = keccak256("some other migration");
        vm.mockCall(
            REGISTRY_V2,
            abi.encodeCall(IMigrationRegistryV2.head, (safe, LibRbacMigration.STOX_RBAC_NAMESPACE)),
            abi.encode(other)
        );
        vm.expectRevert(
            abi.encodeWithSelector(UnexpectedRegistryV2Line.selector, LibRbacMigration.STOX_RBAC_NAMESPACE, other)
        );
        script.callPreflight();
    }

    function assertRefusesV2Order(ScriptDeclaration memory declared) internal {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        bytes32 other = keccak256("some other migration");
        vm.mockCall(
            REGISTRY_V2,
            abi.encodeCall(IMigrationRegistryV2.appliedOnto, (safe, declared.namespace, declared.id)),
            abi.encode(other)
        );
        bytes memory refusal = abi.encodeWithSelector(UnexpectedRegistryV2Order.selector, declared.id, other);
        vm.expectRevert(refusal);
        script.callPreflight();
        vm.expectRevert(refusal);
        script.callAuthorBundle();
    }

    function testRefusesGovernanceTimelockOutOfV2Order() external {
        assertRefusesV2Order(migrateGovernanceToTimelockDeclaration());
    }

    function testRefusesOrchestratorEmergencyOutOfV2Order() external {
        assertRefusesV2Order(grantOrchestratorEmergencyDeclaration());
    }

    function testRefusesEuAuthoriserGrantOutOfV2Order() external {
        assertRefusesV2Order(grantEuAuthoriserRolesDeclaration());
    }

    function testRefusesGovernanceTimelockMomentMismatch() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        (uint256 pinned,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);
        vm.mockCall(
            REGISTRY_V2,
            abi.encodeCall(
                IMigrationRegistryV2.applied, (safe, LibStoxMigrations.NAMESPACE, LibStoxMigrations.GOVERNANCE_TIMELOCK)
            ),
            abi.encode(pinned + 1)
        );
        vm.expectRevert(abi.encodeWithSelector(GovernanceTimelockMomentMismatch.selector, pinned, pinned + 1));
        script.callPreflight();
    }

    function testPreflightRefusesSafeOffPolicy() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        vm.mockCall(safe, abi.encodeWithSignature("getThreshold()"), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector, safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD, 1
            )
        );
        script.callPreflight();
    }

    function testPreflightRefusesTimelockOffState() external {
        (BackfillMigrationRegistryV5Harness script,) = setUpBase();
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.mockCall(timelock, abi.encodeCall(ITimelockControllerState.getMinDelay, ()), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMinDelayMismatch.selector,
                timelock,
                LibTimelockInvariants.TIMELOCK_MIN_DELAY,
                1
            )
        );
        script.callPreflight();
    }

    function testVerifyRefusesTamperedArtifact() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent(safe)) return;
        string memory json =
            LibSafeTxBuilderJson.toJson(vm, safe, block.chainid, "tamper test", script.callAuthorBundle());
        string memory cleanPath =
            string.concat("out/20261030-backfill-migration-registry-v5-clean-", vm.toString(block.chainid), ".json");
        vm.writeFile(cleanPath, json);
        script.verify(cleanPath);
        bytes32 rbac = LibRbacMigration.STOX_RBAC_NAMESPACE;
        bytes32 eu = LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER;
        uint256 euAt = V2.applied(safe, rbac, eu);
        string memory tampered = vm.replace(
            json,
            vm.toString(historyData(safe, rbac, eu, euAt, MIGRATION_HEAD_GENESIS)),
            vm.toString(historyData(safe, rbac, eu, euAt - 1, MIGRATION_HEAD_GENESIS))
        );
        assertTrue(keccak256(bytes(tampered)) != keccak256(bytes(json)), "tamper did not apply");
        string memory tamperedPath =
            string.concat("out/20261030-backfill-migration-registry-v5-tampered-", vm.toString(block.chainid), ".json");
        vm.writeFile(tamperedPath, tampered);
        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.ArtifactMismatch.selector, "data"));
        script.verify(tamperedPath);
    }

    function testPostStateRefusesUnreplayedRecord() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent(safe)) return;
        vm.expectRevert(
            abi.encodeWithSelector(
                BackfillV5RecordMismatch.selector,
                LibStoxMigrations.GOVERNANCE_TIMELOCK,
                V2.applied(safe, LibStoxMigrations.NAMESPACE, LibStoxMigrations.GOVERNANCE_TIMELOCK),
                0
            )
        );
        script.callAssertPostState();
    }

    /// @dev Record `index` replayed one second before its V2 moment is refused.
    function assertPostStateRefusesMisreplayed(uint256 index) internal {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent(safe)) return;
        ScriptDeclaration memory declared = v2Records()[index];
        SafeTx[] memory txs = script.callAuthorBundle();
        uint256 v2At = v2Moment(safe, declared);
        txs[index].data =
            historyData(safe, declared.namespace, declared.id, v2At - 1, declared.prerequisites[0].migration);
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);
        vm.expectRevert(abi.encodeWithSelector(BackfillV5RecordMismatch.selector, declared.id, v2At, v2At - 1));
        script.callAssertPostState();
    }

    function testPostStateRefusesMisreplayedGovernanceTimelock() external {
        assertPostStateRefusesMisreplayed(0);
    }

    function testPostStateRefusesMisreplayedOrchestratorEmergency() external {
        assertPostStateRefusesMisreplayed(1);
    }

    function testPostStateRefusesMisreplayedEuAuthoriserGrant() external {
        assertPostStateRefusesMisreplayed(2);
    }

    function testPostStateRefusesMissingOwnRecord() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent(safe)) return;
        SafeTx[] memory txs = script.callAuthorBundle();
        SafeTx[] memory history = new SafeTx[](txs.length - 1);
        for (uint256 i = 0; i < history.length; i++) {
            history[i] = txs[i];
        }
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), history);
        vm.expectRevert(
            abi.encodeWithSelector(BackfillV5RecordMissing.selector, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5)
        );
        script.callAssertPostState();
    }

    function testPostStateRefusesSafeOffPolicy() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent(safe)) return;
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        script.callAssertPostState();
        vm.mockCall(safe, abi.encodeWithSignature("getThreshold()"), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector, safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD, 1
            )
        );
        script.callAssertPostState();
    }
}
