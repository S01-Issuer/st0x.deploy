// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {IMigrationRegistryV5, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";

import {IStoxScript, ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {
    LibStoxMigrations,
    LineHeadMismatch,
    RecordMismatch,
    SafeNotApprovedWriter,
    UnexpectedMigrationLine
} from "../../src/lib/LibStoxMigrations.sol";
import {LibTestRootLine} from "./LibTestRootLine.sol";

/// @dev The hooks a record script's harness exposes.
interface IRecordScriptHooks {
    function callPreflight() external view;

    function callAuthorBundle() external view returns (SafeTx[] memory);

    function callAssertPostState() external view;
}

/// @title RootLineRecordScriptTest
/// @notice The root-line contract every record script keeps: it declares
/// `id` onto `onto`, its pre-flight refuses any line not at `onto` and a Safe
/// the root does not approve, its bundle ends with its record, and its
/// post-state refuses the record missing, stamped at another moment or buried.
/// `setUp` brings the chain to just before `onto` lands, snapshots, then lands
/// it.
abstract contract RootLineRecordScriptTest is Test {
    IRecordScriptHooks internal sScript;
    uint256 internal sBeforeOnto;

    function newScript() internal virtual returns (IRecordScriptHooks);

    function declaredId() internal pure virtual returns (bytes32);

    function declaredOnto() internal pure virtual returns (bytes32);

    /// @dev Everything the pre-flight needs except the `onto` record.
    function landBeforeOnto() internal virtual;

    function landOnto() internal virtual;

    /// @dev Re-stamps now any state besides the record that the post-state
    /// pins to the landing block.
    function restampAtThisMoment() internal virtual {}

    function latestRecordAge() internal pure virtual returns (uint256) {
        return type(uint32).max;
    }

    function setUp() public virtual {
        landBeforeOnto();
        sScript = newScript();
        sBeforeOnto = vm.snapshotState();
        landOnto();
        assertEq(LibStoxMigrations.head(), declaredOnto(), "line at the onto");
    }

    function safeAddress() internal view returns (address) {
        return LibSafeInvariants.safeForChainId(block.chainid);
    }

    function declared() internal pure returns (ScriptDeclaration memory) {
        return ScriptDeclaration({id: declaredId(), onto: declaredOnto(), history: false});
    }

    function executeBundlePrefix(uint256 count) internal {
        SafeTx[] memory txs = sScript.callAuthorBundle();
        SafeTx[] memory prefix = new SafeTx[](count);
        for (uint256 txIndex = 0; txIndex < count; txIndex++) {
            prefix[txIndex] = txs[txIndex];
        }
        if (count > 0) LibSafeFork.executeBundle(vm, Safe(payable(safeAddress())), prefix);
    }

    function executeBundle() internal {
        executeBundlePrefix(sScript.callAuthorBundle().length);
    }

    function ownRecordPreflightRefusal() internal pure virtual returns (bytes memory) {
        return abi.encodeWithSelector(UnexpectedMigrationLine.selector, declaredId());
    }

    function assumeUnrecorded(bytes32 record) internal view {
        vm.assume(record != bytes32(0) && record != MIGRATION_HEAD_GENESIS && LibStoxMigrations.applied(record) == 0);
    }

    function assumeForeign(bytes32 record) internal view {
        assumeUnrecorded(record);
        vm.assume(record != declaredId());
    }

    function testDeclarationIsItsRootLineRecord(uint256 chainId) external view {
        ScriptDeclaration memory declaration = IStoxScript(address(sScript)).declaration(chainId);
        assertEq(declaration.id, declaredId(), "id");
        assertEq(declaration.onto, declaredOnto(), "onto");
        assertFalse(declaration.history, "history");
    }

    function testPreflightRefusesTheLineBeforeItsOnto() external {
        assertTrue(vm.revertToState(sBeforeOnto), "snapshot before the onto");
        bytes32 lineHead = LibStoxMigrations.head();
        assertTrue(lineHead != declaredOnto(), "line before the onto");
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, lineHead));
        sScript.callPreflight();
    }

    function assertPreflightRefusesTheLineMovedTo(bytes32 next, bytes memory refusal) internal {
        sScript.callPreflight();
        LibTestRootLine.write(vm, safeAddress(), next, declaredOnto());
        vm.expectRevert(refusal);
        sScript.callPreflight();
    }

    function testPreflightRefusesALineMovedPastItsOnto(bytes32 next) external {
        assumeUnrecorded(next);
        assertPreflightRefusesTheLineMovedTo(
            next,
            next == declaredId()
                ? ownRecordPreflightRefusal()
                : abi.encodeWithSelector(UnexpectedMigrationLine.selector, next)
        );
    }

    function testPreflightRefusesTheLineAtItsOwnRecord() external {
        assertPreflightRefusesTheLineMovedTo(declaredId(), ownRecordPreflightRefusal());
    }

    function testPreflightRefusesASafeTheRootDoesNotApprove() external {
        sScript.callPreflight();
        LibTestRootLine.revoke(vm, safeAddress());
        vm.expectRevert(abi.encodeWithSelector(SafeNotApprovedWriter.selector, safeAddress()));
        sScript.callPreflight();
    }

    function testBundleEndsWithItsRootLineRecord() external view {
        SafeTx[] memory txs = sScript.callAuthorBundle();
        (address registry, bytes memory data) = LibStoxMigrations.recordCall(declared());
        SafeTx memory last = txs[txs.length - 1];
        assertEq(last.to, registry, "record target");
        assertEq(last.value, 0, "record value");
        assertEq(last.data, data, "record calldata");
        assertEq(uint8(last.operation), uint8(Enum.Operation.Call), "record operation");
    }

    function testLandedBundleHeadsTheLineWithItsRecord() external {
        executeBundle();
        assertEq(LibStoxMigrations.applied(declaredId()), block.timestamp, "record stamped at the block");
        assertEq(LibStoxMigrations.head(), declaredId(), "record heads the line");
        sScript.callAssertPostState();
    }

    function testPostStateRefusesTheBundleWithoutItsRecord() external {
        executeBundlePrefix(sScript.callAuthorBundle().length - 1);
        vm.expectRevert(abi.encodeWithSelector(RecordMismatch.selector, declaredId(), block.timestamp, 0));
        sScript.callAssertPostState();
    }

    function testPostStateRefusesARecordFromAnotherMoment(uint256 later) external {
        later = bound(later, 1, latestRecordAge());
        executeBundle();
        uint256 recorded = block.timestamp;
        vm.warp(recorded + later);
        restampAtThisMoment();
        vm.expectRevert(abi.encodeWithSelector(RecordMismatch.selector, declaredId(), recorded + later, recorded));
        sScript.callAssertPostState();
    }

    function testPostStateRefusesALineMovedPastItsRecord(bytes32 next) external {
        assumeForeign(next);
        executeBundle();
        LibTestRootLine.write(vm, safeAddress(), next, declaredId());
        vm.expectRevert(abi.encodeWithSelector(LineHeadMismatch.selector, next));
        sScript.callAssertPostState();
    }

    function testNoZeroOrGenesisRecordLandsOnItsOntoOrItsRecord() external {
        assertZeroAndGenesisRefusedOnto(declaredOnto());
        executeBundle();
        assertZeroAndGenesisRefusedOnto(declaredId());
        assertEq(LibStoxMigrations.head(), declaredId(), "line unmoved");
    }

    function assertZeroAndGenesisRefusedOnto(bytes32 onto) internal {
        vm.expectRevert(IMigrationRegistryV5.ZeroMigration.selector);
        LibTestRootLine.write(vm, safeAddress(), bytes32(0), onto);
        vm.expectRevert(IMigrationRegistryV5.GenesisMigration.selector);
        LibTestRootLine.write(vm, safeAddress(), MIGRATION_HEAD_GENESIS, onto);
    }
}
