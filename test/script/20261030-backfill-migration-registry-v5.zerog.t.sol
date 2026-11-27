// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {
    BYTECODE_HASH as REGISTRY_V2_CODEHASH,
    DEPLOYED_ADDRESS as REGISTRY_V2,
    RUNTIME_CODE as REGISTRY_V2_RUNTIME_CODE
} from "rain-deploy-0.1.41/src/generated/0_1_18/MigrationRegistry.sol";
import {IMigrationRegistryV2, Prerequisite} from "rain-deploy-0.1.41/src/interface/deprecated/IMigrationRegistryV2.sol";
import {IMigrationRegistryV5, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.41/src/interface/IMigrationRegistryV5.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.41/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.41/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.41/src/lib/LibRegistryAuthority.sol";
import {LibSafe} from "rain-deploy-0.1.41/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.41/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.41/src/lib/LibSafeTxBuilderJson.sol";
import {SafeTx} from "rain-deploy-0.1.41/src/lib/LibSafeTx.sol";

import {
    UnexpectedRegistryV2CodeHash,
    UnexpectedRegistryV2Line,
    V2_RBAC_NAMESPACE,
    backfillMigrationRegistryV5Declaration
} from "../../script/20261030-backfill-migration-registry-v5.s.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {ZerogTokenCreationFixture} from "./ZerogTokenCreationFixture.sol";

/// @title BackfillMigrationRegistryV5ZerogTest
/// @notice On 0G, which ran none of the history and never had the V2 registry, the backfill writes the same records
/// as every chain off Base, in the same order, each record-only, then its own record: 0G's line then holds every other
/// chain's records up to the backfill.
contract BackfillMigrationRegistryV5ZerogTest is ZerogTokenCreationFixture {
    address internal constant V5 = LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS;
    address internal constant ROOT = LibRegistryAuthority.ROOT_AUTHORITY;
    bytes32 internal constant NS = LibStoxMigrations.NAMESPACE;
    bytes32 internal constant OWN = LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5;

    BackfillMigrationRegistryV5Harness internal sScript;

    function setUp() external {
        buildZerog();
        sScript = new BackfillMigrationRegistryV5Harness("zerog");
    }

    function safe() internal pure returns (address) {
        return LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ZEROG;
    }

    /// @dev The records before the backfill's own, in the order every chain off Base writes them.
    function offBaseLine() internal pure returns (bytes32[7] memory) {
        return [
            LibStoxMigrations.MULTISIG_THRESHOLD,
            LibStoxMigrations.GOVERNANCE_TIMELOCK,
            LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES,
            LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
            LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE,
            LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL,
            LibStoxMigrations.EXECUTE_TIMELOCK_OPERATIONS
        ];
    }

    function recordData(bytes32 id, bytes32 onto) internal pure returns (bytes memory) {
        return abi.encodeCall(
            IMigrationRegistryV5.applyMigrationV5, (ROOT, NS, id, LibMigrationRegistry.onto(ROOT, NS, onto), "")
        );
    }

    function testZerogIsWithoutHistory() external view {
        assertEq(block.chainid, LibSafeInvariants.ZEROG_CHAIN_ID, "on 0G");
        assertTrue(LibStoxMigrations.withoutHistory(block.chainid), "0G has no history");
        assertEq(REGISTRY_V2.code.length, 0, "no V2 registry on 0G");
        assertEq(LibStoxMigrations.head(), MIGRATION_HEAD_GENESIS, "0G line empty");
    }

    function testDeclarationIsOntoTheOffBaseLastRecord() external pure {
        ScriptDeclaration memory declared = backfillMigrationRegistryV5Declaration(LibSafeInvariants.ZEROG_CHAIN_ID);
        assertEq(declared.id, OWN, "id");
        assertEq(declared.onto, LibStoxMigrations.EXECUTE_TIMELOCK_OPERATIONS, "onto");
        assertFalse(declared.history, "record-only");
    }

    /// @notice Every record record-only, onto the one before it from genesis, then the backfill's own.
    function testBundleIsTheOffBaseLineRecordOnly() external view {
        sScript.callPreflight();
        SafeTx[] memory txs = sScript.callAuthorBundle();
        bytes32[7] memory line = offBaseLine();
        assertEq(txs.length, line.length + 1, "bundle length");
        bytes32 onto = MIGRATION_HEAD_GENESIS;
        for (uint256 i = 0; i < txs.length; i++) {
            bytes32 id = i < line.length ? line[i] : OWN;
            assertEq(txs[i].to, V5, "to the V5 registry");
            assertEq(txs[i].value, 0, "no value");
            assertEq(uint8(txs[i].operation), uint8(Enum.Operation.Call), "call");
            assertEq(txs[i].data, recordData(id, onto), "record-only calldata");
            onto = id;
        }
    }

    /// @notice `run()` writes the artifact `verify` accepts; executed, it leaves 0G's line at the backfill, each
    /// record stamped at the bundle's block and written by the Safe, and re-authoring is then empty.
    function testExecutedBundleLeavesTheLineAtTheBackfill() external {
        uint256 preRun = vm.snapshotState();
        sScript.run();
        vm.revertToState(preRun);
        string memory artifactPath = sScript.callArtifactPath();
        sScript.verify(artifactPath);
        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, safe(), "artifact Safe");
        LibSafeFork.executeBundle(vm, Safe(payable(safe())), txs);

        bytes32[7] memory line = offBaseLine();
        bytes32 onto = MIGRATION_HEAD_GENESIS;
        for (uint256 i = 0; i <= line.length; i++) {
            bytes32 id = i < line.length ? line[i] : OWN;
            assertEq(LibStoxMigrations.applied(id), block.timestamp, "record-only, live");
            assertEq(LibMigrationRegistry.appliedOntoV5(ROOT, NS, id), onto, "onto the line");
            assertEq(LibMigrationRegistry.appliedByV5(ROOT, NS, id), safe(), "written by the Safe");
            onto = id;
        }
        assertEq(LibStoxMigrations.head(), OWN, "line head");
        sScript.callAssertPostState();
        assertEq(sScript.callAuthorBundle().length, 0, "re-authoring after execution is empty");
    }

    /// @notice Other code at the V2 address on 0G is refused: its records could not be read.
    function testPreflightRefusesOtherCodeAtTheRegistryV2Address() external {
        vm.etch(REGISTRY_V2, hex"00");
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRegistryV2CodeHash.selector, keccak256(hex"00")));
        sScript.callPreflight();
    }

    /// @dev The frozen V2 registry at its Zoltu address, as anyone can deploy it on 0G.
    function etchRegistryV2() internal {
        vm.etch(REGISTRY_V2, REGISTRY_V2_RUNTIME_CODE);
        assertEq(REGISTRY_V2.codehash, REGISTRY_V2_CODEHASH, "the frozen V2 registry");
    }

    /// @notice The V2 address is a public Zoltu deploy. The frozen V2 registry there, with no record of the Safe, does
    /// not stop the 0G backfill, and the bundle is the same.
    function testAFrozenRegistryV2WithoutTheSafesRecordsDoesNotStopTheBackfill() external {
        SafeTx[] memory without = sScript.callAuthorBundle();
        etchRegistryV2();
        vm.prank(address(0xBEEF));
        Prerequisite[] memory onto = new Prerequisite[](1);
        onto[0] = Prerequisite({writer: address(0xBEEF), namespace: NS, migration: MIGRATION_HEAD_GENESIS});
        IMigrationRegistryV2(REGISTRY_V2).applyMigration(NS, OWN, onto);
        sScript.callPreflight();
        SafeTx[] memory with = sScript.callAuthorBundle();
        assertEq(keccak256(abi.encode(with)), keccak256(abi.encode(without)), "same bundle");
    }

    /// @notice A V2 record of the 0G Safe, on either V2 line, is refused: the backfill would not carry it over.
    function testPreflightRefusesARegistryV2RecordOfTheSafe(bool rbac) external {
        etchRegistryV2();
        bytes32 namespace = rbac ? V2_RBAC_NAMESPACE : NS;
        Prerequisite[] memory onto = new Prerequisite[](1);
        onto[0] = Prerequisite({writer: safe(), namespace: namespace, migration: MIGRATION_HEAD_GENESIS});
        vm.prank(safe());
        IMigrationRegistryV2(REGISTRY_V2).applyMigration(namespace, OWN, onto);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRegistryV2Line.selector, namespace, OWN));
        sScript.callPreflight();
    }

    /// @notice 0G's Safe moves from 1-of-6 to 3-of-6 before the backfill records the threshold migration there.
    function testPreflightRefusesTheSafeBeforeItsThreshold() external {
        vm.prank(safe());
        Safe(payable(safe())).changeThreshold(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector, safe(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD, 1
            )
        );
        sScript.callPreflight();
    }
}
