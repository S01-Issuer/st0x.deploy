// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV2} from "rain-deploy-0.1.30/src/interface/deprecated/IMigrationRegistryV2.sol";
import {DEPLOYED_ADDRESS as REGISTRY_V2} from "rain-deploy-0.1.30/src/generated/0_1_18/MigrationRegistry.sol";
import {IMigrationRegistryV5, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafe} from "rain-deploy-0.1.30/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.30/src/lib/LibSafeTxBuilderJson.sol";
import {ITimelockControllerState, LibTimelockController} from "rain-deploy-0.1.30/src/lib/LibTimelockController.sol";

import {
    BackfillV5OrderMismatch,
    BackfillV5RecordMismatch,
    BackfillV5RecordMissing,
    HistoryMomentMismatch,
    UnexpectedRegistryV2CodeHash,
    UnexpectedRegistryV2Line,
    UnexpectedRegistryV2Order,
    V2_EU_AUTHORISER_GRANT_AND_HANDOVER,
    V2_RBAC_NAMESPACE,
    backfillMigrationRegistryV5Declaration
} from "../../script/20261030-backfill-migration-registry-v5.s.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {IStoxHistoryMigration, IStoxScript, ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

struct LineRecord {
    bytes32 id;
    bool history;
}

struct V2Record {
    bytes32 id;
    bytes32 v2Namespace;
    bytes32 v2Id;
}

/// @title BackfillMigrationRegistryV5Test
/// @notice Per chain: the bundle writes the chain's records onto the root line
/// in line order, each history record at its script's moment, the rehearsal
/// records record-only off Base, skips what V5 holds, and ends with its own
/// record; the script refuses a V2 state or a line it does not carry over.
contract BackfillMigrationRegistryV5Test is Test {
    IMigrationRegistryV2 internal constant V2 = IMigrationRegistryV2(REGISTRY_V2);
    address internal constant V5 = LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS;
    address internal constant ROOT = LibRegistryAuthority.ROOT_AUTHORITY;
    bytes32 internal constant NS = LibStoxMigrations.NAMESPACE;
    bytes32 internal constant OWN = LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5;
    bytes32 internal constant OTHER = keccak256("some other migration");

    function line(uint256 chainId) internal pure returns (LineRecord[] memory) {
        LineRecord[] memory all = new LineRecord[](7);
        all[0] = LineRecord(LibStoxMigrations.MULTISIG_THRESHOLD, true);
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) {
            all[1] = LineRecord(LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE, true);
            all[2] = LineRecord(LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL, true);
            all[3] = LineRecord(LibStoxMigrations.EXECUTE_TIMELOCK_OPERATIONS, true);
            all[4] = LineRecord(LibStoxMigrations.GOVERNANCE_TIMELOCK, true);
            all[5] = LineRecord(LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES, true);
            all[6] = LineRecord(LibStoxMigrations.ORCHESTRATOR_EMERGENCY, true);
        } else {
            all[1] = LineRecord(LibStoxMigrations.GOVERNANCE_TIMELOCK, true);
            all[2] = LineRecord(LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES, true);
            all[3] = LineRecord(LibStoxMigrations.ORCHESTRATOR_EMERGENCY, true);
            all[4] = LineRecord(LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE, false);
            all[5] = LineRecord(LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL, false);
            all[6] = LineRecord(LibStoxMigrations.EXECUTE_TIMELOCK_OPERATIONS, false);
        }
        return all;
    }

    function v2Records() internal pure returns (V2Record[] memory) {
        V2Record[] memory all = new V2Record[](3);
        all[0] = V2Record(LibStoxMigrations.GOVERNANCE_TIMELOCK, NS, LibStoxMigrations.GOVERNANCE_TIMELOCK);
        all[1] = V2Record(
            LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES, V2_RBAC_NAMESPACE, V2_EU_AUTHORISER_GRANT_AND_HANDOVER
        );
        all[2] = V2Record(LibStoxMigrations.ORCHESTRATOR_EMERGENCY, NS, LibStoxMigrations.ORCHESTRATOR_EMERGENCY);
        return all;
    }

    function ontoAt(LineRecord[] memory all, uint256 i) internal pure returns (bytes32) {
        return i == 0 ? MIGRATION_HEAD_GENESIS : all[i - 1].id;
    }

    function momentOf(BackfillMigrationRegistryV5Harness script, bytes32 id) internal view returns (uint256) {
        return IStoxHistoryMigration(script.scriptOf(id)).executedAt(block.chainid);
    }

    function historyData(bytes32 id, uint256 at, bytes32 onto) internal pure returns (bytes memory) {
        return abi.encodeCall(
            IMigrationRegistryV5.applyMigrationHistoryV5,
            (ROOT, NS, id, at, LibMigrationRegistry.onto(ROOT, NS, onto), "")
        );
    }

    function recordData(bytes32 id, bytes32 onto) internal pure returns (bytes memory) {
        return abi.encodeCall(
            IMigrationRegistryV5.applyMigrationV5, (ROOT, NS, id, LibMigrationRegistry.onto(ROOT, NS, onto), "")
        );
    }

    /// @dev The bundle once V5 holds the line's first `held` records.
    function expectedBundle(BackfillMigrationRegistryV5Harness script, uint256 held)
        internal
        view
        returns (bytes[] memory)
    {
        LineRecord[] memory all = line(block.chainid);
        bytes[] memory expected = new bytes[](all.length - held + 1);
        for (uint256 i = held; i < all.length; i++) {
            expected[i - held] = all[i].history
                ? historyData(all[i].id, momentOf(script, all[i].id), ontoAt(all, i))
                : recordData(all[i].id, ontoAt(all, i));
        }
        expected[expected.length - 1] = recordData(OWN, all[all.length - 1].id);
        return expected;
    }

    function assertBundle(SafeTx[] memory txs, bytes[] memory expected) internal pure {
        assertEq(txs.length, expected.length, "bundle length");
        for (uint256 i = 0; i < txs.length; i++) {
            assertEq(txs[i].to, V5, "to the V5 registry");
            assertEq(txs[i].value, 0, "no value");
            assertEq(uint8(txs[i].operation), uint8(Enum.Operation.Call), "call");
            assertEq(txs[i].data, expected[i], "calldata");
        }
    }

    function holdAt(address safe, bytes32 id, uint256 at, bytes32 onto) internal {
        vm.prank(safe);
        IMigrationRegistryV5(V5)
            .applyMigrationHistoryV5(ROOT, NS, id, at, LibMigrationRegistry.onto(ROOT, NS, onto), "");
    }

    /// @dev V5 holds the line's first `held` records as the bundle writes them.
    function holdPrefix(BackfillMigrationRegistryV5Harness script, address safe, uint256 held) internal {
        LineRecord[] memory all = line(block.chainid);
        for (uint256 i = 0; i < held; i++) {
            if (all[i].history) holdAt(safe, all[i].id, momentOf(script, all[i].id), ontoAt(all, i));
            else LibTestRootLine.write(vm, safe, all[i].id, ontoAt(all, i));
        }
    }

    function assertLine(BackfillMigrationRegistryV5Harness script, address safe) internal view {
        LineRecord[] memory all = line(block.chainid);
        for (uint256 i = 0; i < all.length; i++) {
            uint256 at = LibStoxMigrations.applied(all[i].id);
            assertTrue(at != 0, "V5 holds the record");
            if (all[i].history) assertEq(at, momentOf(script, all[i].id), "history at its script's moment");
            assertEq(LibMigrationRegistry.appliedOntoV5(ROOT, NS, all[i].id), ontoAt(all, i), "onto the line");
            assertEq(LibMigrationRegistry.appliedByV5(ROOT, NS, all[i].id), safe, "written by the Safe");
        }
        V2Record[] memory v2 = v2Records();
        for (uint256 i = 0; i < v2.length; i++) {
            assertEq(
                LibStoxMigrations.applied(v2[i].id),
                V2.applied(safe, v2[i].v2Namespace, v2[i].v2Id),
                "V5 moment is the V2 moment"
            );
        }
        assertTrue(LibStoxMigrations.applied(OWN) != 0, "own record");
        assertEq(LibMigrationRegistry.appliedOntoV5(ROOT, NS, OWN), all[all.length - 1].id, "own record last");
        assertEq(LibMigrationRegistry.appliedByV5(ROOT, NS, OWN), safe, "own record by the Safe");
    }

    function spent() internal view returns (bool) {
        if (LibStoxMigrations.applied(OWN) != 0) {
            console2.log("SPENT: the V5 backfill has executed on this chain");
            return true;
        }
        return false;
    }

    function assertBackfill(string memory network) internal {
        vm.createSelectFork(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        BackfillMigrationRegistryV5Harness script = new BackfillMigrationRegistryV5Harness(network);

        if (spent()) {
            assertLine(script, safe);
            assertEq(script.callAuthorBundle().length, 0, "nothing left to write");
            script.callAssertPostState();
            return;
        }

        assertEq(LibStoxMigrations.head(), MIGRATION_HEAD_GENESIS, "root line starts at genesis");
        assertBundle(script.callAuthorBundle(), expectedBundle(script, 0));

        uint256 preRun = vm.snapshotState();
        script.run();
        vm.revertToState(preRun);

        string memory artifactPath = script.callArtifactPath();
        string memory json = vm.readFile(artifactPath);
        assertEq(vm.parseJsonString(json, ".meta.name"), "ST0x: backfill MigrationRegistry V5 root line");
        script.verify(artifactPath);

        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, json);
        assertEq(artifactSafe, safe, "artifact Safe");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        assertLine(script, safe);
        LineRecord[] memory all = line(block.chainid);
        for (uint256 i = 0; i < all.length; i++) {
            if (!all[i].history) assertEq(LibStoxMigrations.applied(all[i].id), block.timestamp, "record-only, live");
        }
        assertEq(LibStoxMigrations.applied(OWN), block.timestamp, "own record live");
        assertEq(LibStoxMigrations.head(), OWN, "root line head");
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

    function setUpFork(string memory network) internal returns (BackfillMigrationRegistryV5Harness, address) {
        vm.createSelectFork(network);
        return (new BackfillMigrationRegistryV5Harness(network), LibSafeInvariants.safeForChainId(block.chainid));
    }

    function setUpBase() internal returns (BackfillMigrationRegistryV5Harness, address) {
        return setUpFork(LibRainDeploy.BASE);
    }

    function assertBundleSkipsHeldRecords(string memory network) internal {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpFork(network);
        if (spent()) return;
        uint256 count = line(block.chainid).length;
        for (uint256 held = 0; held <= count; held++) {
            uint256 snapshot = vm.snapshotState();
            holdPrefix(script, safe, held);
            assertBundle(script.callAuthorBundle(), expectedBundle(script, held));
            vm.revertToState(snapshot);
        }
        holdPrefix(script, safe, count);
        LibTestRootLine.write(vm, safe, OWN, line(block.chainid)[count - 1].id);
        assertEq(script.callAuthorBundle().length, 0, "V5 holds every record");
        script.callAssertPostState();
    }

    function testBundleSkipsRecordsV5HoldsBase() external {
        assertBundleSkipsHeldRecords(LibRainDeploy.BASE);
    }

    function testBundleSkipsRecordsV5HoldsEthereum() external {
        assertBundleSkipsHeldRecords(LibStoxDeployNetworks.ETHEREUM);
    }

    function testDeclarationIsLiveOntoTheChainsLastBackfilledRecord() external {
        BackfillMigrationRegistryV5Harness script = new BackfillMigrationRegistryV5Harness("declaration");
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            ScriptDeclaration memory declared = backfillMigrationRegistryV5Declaration(chainId);
            assertEq(declared.id, OWN, "id is the script path");
            assertFalse(declared.history, "recorded live");
            assertEq(
                declared.onto,
                chainId == LibSafeInvariants.BASE_CHAIN_ID
                    ? LibStoxMigrations.ORCHESTRATOR_EMERGENCY
                    : LibStoxMigrations.EXECUTE_TIMELOCK_OPERATIONS,
                "onto the chain's last backfilled record"
            );
            LineRecord[] memory all = line(chainId);
            assertEq(declared.onto, all[all.length - 1].id, "after the backfilled line");
            ScriptDeclaration memory viaScript = script.declaration(chainId);
            assertEq(viaScript.id, declared.id, "script declaration id");
            assertEq(viaScript.onto, declared.onto, "script declaration onto");
            assertEq(viaScript.history, declared.history, "script declaration history");
        }
    }

    function testPreflightRefusesAHistoryMomentBeforeThePreviousRecord() external {
        (BackfillMigrationRegistryV5Harness script,) = setUpBase();
        uint256 thresholdAt = momentOf(script, LibStoxMigrations.MULTISIG_THRESHOLD);
        vm.mockCall(
            script.scriptOf(LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE),
            abi.encodeCall(IStoxHistoryMigration.executedAt, (block.chainid)),
            abi.encode(thresholdAt - 1)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                UnexpectedRegistryV2Order.selector,
                LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE,
                LibStoxMigrations.MULTISIG_THRESHOLD
            )
        );
        script.callPreflight();
    }

    function testPreflightAcceptsAHistoryMomentEqualToThePreviousRecord() external {
        (BackfillMigrationRegistryV5Harness script,) = setUpBase();
        vm.mockCall(
            script.scriptOf(LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE),
            abi.encodeCall(IStoxHistoryMigration.executedAt, (block.chainid)),
            abi.encode(momentOf(script, LibStoxMigrations.MULTISIG_THRESHOLD))
        );
        script.callPreflight();
    }

    function testPreflightRefusesARecordDeclaredOntoAnotherThanThePreviousRecord() external {
        (BackfillMigrationRegistryV5Harness script,) = setUpBase();
        vm.mockCall(
            script.scriptOf(LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL),
            abi.encodeCall(IStoxScript.declaration, (block.chainid)),
            abi.encode(ScriptDeclaration({id: LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL, onto: OTHER, history: true}))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                UnexpectedRegistryV2Order.selector, LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL, OTHER
            )
        );
        script.callPreflight();
    }

    function testPreflightRefusesALineEndingElsewhereThanOwnRecordIsDeclaredOnto() external {
        (BackfillMigrationRegistryV5Harness script,) = setUpBase();
        vm.mockCall(
            script.scriptOf(LibStoxMigrations.ORCHESTRATOR_EMERGENCY),
            abi.encodeCall(IStoxScript.declaration, (block.chainid)),
            abi.encode(ScriptDeclaration({id: OTHER, onto: LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES, history: true}))
        );
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRegistryV2Order.selector, OWN, OTHER));
        script.callPreflight();
    }

    function testRefusesUnpinnedRegistryV2Code() external {
        (BackfillMigrationRegistryV5Harness script,) = setUpBase();
        vm.etch(REGISTRY_V2, hex"00");
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRegistryV2CodeHash.selector, keccak256(hex"00")));
        script.callPreflight();
    }

    function testRefusesUnexpectedV2DeployHead() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        vm.mockCall(REGISTRY_V2, abi.encodeCall(IMigrationRegistryV2.head, (safe, NS)), abi.encode(OTHER));
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRegistryV2Line.selector, NS, OTHER));
        script.callPreflight();
    }

    function testRefusesUnexpectedV2RbacHead() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        vm.mockCall(
            REGISTRY_V2, abi.encodeCall(IMigrationRegistryV2.head, (safe, V2_RBAC_NAMESPACE)), abi.encode(OTHER)
        );
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRegistryV2Line.selector, V2_RBAC_NAMESPACE, OTHER));
        script.callPreflight();
    }

    function assertRefusesV2Order(uint256 index) internal {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        V2Record memory record = v2Records()[index];
        vm.mockCall(
            REGISTRY_V2,
            abi.encodeCall(IMigrationRegistryV2.appliedOnto, (safe, record.v2Namespace, record.v2Id)),
            abi.encode(OTHER)
        );
        bytes memory refusal = abi.encodeWithSelector(UnexpectedRegistryV2Order.selector, record.v2Id, OTHER);
        vm.expectRevert(refusal);
        script.callPreflight();
        if (spent()) return;
        vm.expectRevert(refusal);
        script.callAuthorBundle();
    }

    function testRefusesGovernanceTimelockOutOfV2Order() external {
        assertRefusesV2Order(0);
    }

    function testRefusesEuAuthoriserGrantOutOfV2Order() external {
        assertRefusesV2Order(1);
    }

    function testRefusesOrchestratorEmergencyOutOfV2Order() external {
        assertRefusesV2Order(2);
    }

    function assertRefusesV2MomentMismatch(uint256 index) internal {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        V2Record memory record = v2Records()[index];
        uint256 at = momentOf(script, record.id);
        vm.mockCall(
            REGISTRY_V2,
            abi.encodeCall(IMigrationRegistryV2.applied, (safe, record.v2Namespace, record.v2Id)),
            abi.encode(at + 1)
        );
        bytes memory refusal = abi.encodeWithSelector(HistoryMomentMismatch.selector, record.id, at, at + 1);
        vm.expectRevert(refusal);
        script.callPreflight();
        if (spent()) return;
        vm.expectRevert(refusal);
        script.callAuthorBundle();
    }

    function testRefusesGovernanceTimelockMomentMismatch() external {
        assertRefusesV2MomentMismatch(0);
    }

    function testRefusesEuAuthoriserGrantMomentMismatch() external {
        assertRefusesV2MomentMismatch(1);
    }

    function testRefusesOrchestratorEmergencyMomentMismatch() external {
        assertRefusesV2MomentMismatch(2);
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
        if (spent()) return;
        string memory json =
            LibSafeTxBuilderJson.toJson(vm, safe, block.chainid, "tamper test", script.callAuthorBundle());
        string memory cleanPath =
            string.concat("out/20261030-backfill-migration-registry-v5-clean-", vm.toString(block.chainid), ".json");
        vm.writeFile(cleanPath, json);
        script.verify(cleanPath);
        bytes32 threshold = LibStoxMigrations.MULTISIG_THRESHOLD;
        uint256 at = momentOf(script, threshold);
        string memory tampered = vm.replace(
            json,
            vm.toString(historyData(threshold, at, MIGRATION_HEAD_GENESIS)),
            vm.toString(historyData(threshold, at - 1, MIGRATION_HEAD_GENESIS))
        );
        assertTrue(keccak256(bytes(tampered)) != keccak256(bytes(json)), "tamper did not apply");
        string memory tamperedPath =
            string.concat("out/20261030-backfill-migration-registry-v5-tampered-", vm.toString(block.chainid), ".json");
        vm.writeFile(tamperedPath, tampered);
        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.ArtifactMismatch.selector, "data"));
        script.verify(tamperedPath);
    }

    function testPostStateRefusesUnwrittenLine() external {
        (BackfillMigrationRegistryV5Harness script,) = setUpBase();
        if (spent()) return;
        vm.expectRevert(abi.encodeWithSelector(BackfillV5RecordMissing.selector, LibStoxMigrations.MULTISIG_THRESHOLD));
        script.callAssertPostState();
    }

    function testPostStateRefusesHeldHistoryAtAnotherMoment() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent()) return;
        LineRecord[] memory all = line(block.chainid);
        holdPrefix(script, safe, 4);
        bytes32 gov = LibStoxMigrations.GOVERNANCE_TIMELOCK;
        uint256 at = momentOf(script, gov);
        holdAt(safe, gov, at - 1, all[3].id);
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        vm.expectRevert(abi.encodeWithSelector(BackfillV5RecordMismatch.selector, gov, at, at - 1));
        script.callAssertPostState();
    }

    function testPostStateRefusesHeldRecordOntoAnotherPredecessor() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent()) return;
        LineRecord[] memory all = line(block.chainid);
        holdPrefix(script, safe, 4);
        bytes32 gov = LibStoxMigrations.GOVERNANCE_TIMELOCK;
        uint256 at = momentOf(script, gov);
        holdAt(safe, OTHER, at, all[3].id);
        holdAt(safe, gov, at, OTHER);
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        assertEq(LibStoxMigrations.applied(gov), at, "V5 moment is the script's moment");
        vm.expectRevert(abi.encodeWithSelector(BackfillV5OrderMismatch.selector, gov, OTHER));
        script.callAssertPostState();
    }

    function testPostStateRefusesMissingOwnRecord() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent()) return;
        SafeTx[] memory txs = script.callAuthorBundle();
        SafeTx[] memory history = new SafeTx[](txs.length - 1);
        for (uint256 i = 0; i < history.length; i++) {
            history[i] = txs[i];
        }
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), history);
        vm.expectRevert(abi.encodeWithSelector(BackfillV5RecordMissing.selector, OWN));
        script.callAssertPostState();
    }

    function testPostStateRefusesOwnRecordOntoAnotherRecord() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent()) return;
        uint256 count = line(block.chainid).length;
        holdPrefix(script, safe, count);
        LibTestRootLine.write(vm, safe, OTHER, line(block.chainid)[count - 1].id);
        LibTestRootLine.write(vm, safe, OWN, OTHER);
        assertEq(script.callAuthorBundle().length, 0, "V5 holds every record");
        vm.expectRevert(abi.encodeWithSelector(BackfillV5OrderMismatch.selector, OWN, OTHER));
        script.callAssertPostState();
    }

    function testPostStateRefusesSafeOffPolicy() external {
        (BackfillMigrationRegistryV5Harness script, address safe) = setUpBase();
        if (spent()) return;
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

    function testArtifactIsTheChainsJsonUnderOut() external {
        BackfillMigrationRegistryV5Harness script = new BackfillMigrationRegistryV5Harness("path");
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            assertEq(
                script.callScriptArtifactPath(),
                string.concat("out/20261030-backfill-migration-registry-v5-", vm.toString(networks[i].chainId), ".json")
            );
        }
    }
}
