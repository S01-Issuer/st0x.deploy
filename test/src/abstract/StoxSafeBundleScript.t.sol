// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibSafeTx, SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";

import {createZerogTokensDeclaration} from "../../../script/20261119-create-zerog-tokens.s.sol";
import {
    scheduleZerogOrchestratorRolesDeclaration
} from "../../../script/20261123-schedule-zerog-orchestrator-roles.s.sol";
import {
    SafeQueueHashMismatch,
    SafeQueueMalformed,
    SafeQueueNonceMismatch
} from "../../../src/abstract/StoxSafeBundleScript.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations, UnexpectedMigrationLine} from "../../../src/lib/LibStoxMigrations.sol";
import {StoxSafeBundleScriptHarness} from "../../concrete/StoxSafeBundleScriptHarness.sol";
import {ScheduleZerogOrchestratorRolesHarness} from "../../script/ScheduleZerogOrchestratorRolesHarness.sol";

struct QueueEntry {
    SafeTx txn;
    uint256 nonce;
    bytes32 safeTxHash;
}

/// @dev Each field holds its entries JSON-encoded as the Safe Transaction Service returns them.
struct QueueFile {
    string[] to;
    string[] value;
    string[] data;
    string[] operation;
    string[] nonce;
    string[] safeTxHash;
}

/// @dev `vm.setEnv` is process-wide, so `SAFE_QUEUE` is set by one test only.
contract StoxSafeBundleScriptTest is Test {
    uint256 internal constant ETHEREUM_BLOCK = 26491000;
    uint256 internal constant FIELD_COUNT = 6;
    uint256 internal constant TRANSFER_VALUE = 1 ether;

    StoxSafeBundleScriptHarness internal sScript;
    uint256 internal sAtFork;

    function ethereumSafe() internal pure returns (Safe) {
        return Safe(payable(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM));
    }

    function recipient() internal pure returns (address) {
        return address(uint160(uint256(keccak256("safe-queue-recipient"))));
    }

    function testQueueSafeIsTheChainSafe() external {
        StoxSafeBundleScriptHarness script = new StoxSafeBundleScriptHarness();
        vm.chainId(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        assertEq(script.queueSafe(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM, "Ethereum");
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        assertEq(script.queueSafe(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, "Base");
    }

    function testSetUpExecutesTheSafeQueue() external {
        assertFalse(vm.envExists("SAFE_QUEUE"), "SAFE_QUEUE unset before the test");
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM, ETHEREUM_BLOCK);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5, "line at the backfill");
        assertGt(ethereumSafe().nonce(), 0, "Safe has executed");
        assertEq(recipient().balance, 0, "recipient empty");
        assertEq(recipient().code.length, 0, "recipient has no code");
        sScript = new StoxSafeBundleScriptHarness();
        sAtFork = vm.snapshotState();

        checkNoQueueExecutesNothing();
        checkOneTxQueueExecutes();
        checkTwoTxQueueExecutesInOrder();
        checkMismatchedLengthsRevert();
        checkNonceMismatchReverts();
        checkHashMismatchReverts();
        checkScheduleAuthorsOnTheQueuedTokenRecord();

        vm.setEnv("SAFE_QUEUE", "");
    }

    function checkNoQueueExecutesNothing() internal {
        vm.revertToState(sAtFork);
        uint256 live = ethereumSafe().nonce();

        sScript.setUp();
        assertEq(ethereumSafe().nonce(), live, "unset: nonce");

        vm.setEnv("SAFE_QUEUE", "");
        sScript.setUp();
        assertEq(ethereumSafe().nonce(), live, "empty: nonce");

        string memory missing = "out/stox-safe-bundle-script-missing.json";
        if (vm.exists(missing)) vm.removeFile(missing);
        vm.setEnv("SAFE_QUEUE", missing);
        sScript.setUp();
        assertEq(ethereumSafe().nonce(), live, "missing file: nonce");

        vm.setEnv("SAFE_QUEUE", writeQueue("no-entries", queueFile(new QueueEntry[](0))));
        sScript.setUp();
        assertEq(ethereumSafe().nonce(), live, "no entries: nonce");
    }

    function checkOneTxQueueExecutes() internal {
        vm.revertToState(sAtFork);
        uint256 live = ethereumSafe().nonce();
        vm.deal(address(ethereumSafe()), TRANSFER_VALUE);
        QueueEntry[] memory entries = new QueueEntry[](1);
        entries[0] = entry(transferTx(), live);

        vm.setEnv("SAFE_QUEUE", writeQueue("one-tx", queueFile(entries)));
        sScript.setUp();

        assertEq(ethereumSafe().nonce(), live + 1, "one tx: nonce");
        assertEq(recipient().balance, TRANSFER_VALUE, "one tx: transferred");
    }

    function checkTwoTxQueueExecutesInOrder() internal {
        vm.revertToState(sAtFork);
        uint256 live = ethereumSafe().nonce();

        vm.setEnv("SAFE_QUEUE", writeQueue("two-tx", queueFile(twoRecords(live))));
        sScript.setUp();

        assertEq(ethereumSafe().nonce(), live + 2, "two tx: nonce");
        assertEq(LibStoxMigrations.applied(LibStoxMigrations.CREATE_ZEROG_TOKENS), block.timestamp, "first record");
        assertEq(
            LibStoxMigrations.applied(LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES),
            block.timestamp,
            "second record"
        );
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES, "two tx: head");
    }

    function checkMismatchedLengthsRevert() internal {
        for (uint256 field = 0; field < FIELD_COUNT; field++) {
            vm.revertToState(sAtFork);
            uint256 live = ethereumSafe().nonce();
            vm.deal(address(ethereumSafe()), TRANSFER_VALUE);
            QueueEntry[] memory entries = new QueueEntry[](1);
            entries[0] = entry(transferTx(), live);
            QueueFile memory file = withExtraEntry(queueFile(entries), field);

            vm.setEnv("SAFE_QUEUE", writeQueue(string.concat("malformed-", vm.toString(field)), file));
            vm.expectRevert(abi.encodeWithSelector(SafeQueueMalformed.selector));
            sScript.setUp();
        }
    }

    function checkNonceMismatchReverts() internal {
        vm.revertToState(sAtFork);
        uint256 live = ethereumSafe().nonce();
        QueueEntry[] memory entries = new QueueEntry[](1);

        entries[0] = entry(transferTx(), live + 1);
        expectNonceMismatch("nonce-ahead", entries, live, live + 1);

        entries[0] = entry(transferTx(), live - 1);
        expectNonceMismatch("nonce-behind", entries, live, live - 1);

        entries = new QueueEntry[](2);
        entries[0] = entry(transferTx(), live);
        entries[1] = entry(transferTx(), live + 2);
        expectNonceMismatch("nonce-gap", entries, live + 1, live + 2);
    }

    function expectNonceMismatch(string memory name, QueueEntry[] memory entries, uint256 expected, uint256 actual)
        internal
    {
        vm.revertToState(sAtFork);
        vm.deal(address(ethereumSafe()), 2 * TRANSFER_VALUE);
        vm.setEnv("SAFE_QUEUE", writeQueue(name, queueFile(entries)));
        vm.expectRevert(abi.encodeWithSelector(SafeQueueNonceMismatch.selector, expected, actual));
        sScript.setUp();
    }

    function checkHashMismatchReverts() internal {
        vm.revertToState(sAtFork);
        uint256 live = ethereumSafe().nonce();
        QueueEntry[] memory entries = new QueueEntry[](1);
        string[4] memory fields = ["to", "value", "data", "operation"];
        for (uint256 field = 0; field < fields.length; field++) {
            QueueEntry memory signed = entry(transferTx(), live);
            entries[0] = QueueEntry({txn: tampered(signed.txn, field), nonce: live, safeTxHash: signed.safeTxHash});
            expectHashMismatch(
                string.concat("tampered-", fields[field]),
                entries,
                live,
                signed.safeTxHash,
                hashOf(entries[0].txn, live)
            );
        }

        bytes32 atNextNonce = hashOf(transferTx(), live + 1);
        entries[0] = QueueEntry({txn: transferTx(), nonce: live, safeTxHash: atNextNonce});
        expectHashMismatch("hash-at-next-nonce", entries, live, atNextNonce, hashOf(transferTx(), live));

        entries = twoRecords(live);
        bytes32 secondSigned = entries[1].safeTxHash;
        entries[1].txn = tampered(entries[1].txn, 2);
        expectHashMismatch("tampered-second", entries, live + 1, secondSigned, hashOf(entries[1].txn, live + 1));
    }

    function expectHashMismatch(
        string memory name,
        QueueEntry[] memory entries,
        uint256 nonce,
        bytes32 expected,
        bytes32 actual
    ) internal {
        vm.revertToState(sAtFork);
        vm.deal(address(ethereumSafe()), TRANSFER_VALUE + 1);
        vm.setEnv("SAFE_QUEUE", writeQueue(name, queueFile(entries)));
        vm.expectRevert(abi.encodeWithSelector(SafeQueueHashMismatch.selector, nonce, expected, actual));
        sScript.setUp();
    }

    function checkScheduleAuthorsOnTheQueuedTokenRecord() internal {
        vm.revertToState(sAtFork);
        Safe safe = ethereumSafe();
        uint256 live = safe.nonce();
        ScheduleZerogOrchestratorRolesHarness schedule = new ScheduleZerogOrchestratorRolesHarness("safe-queue");
        assertEq(schedule.queueSafe(), address(safe), "schedule queue Safe");

        vm.expectRevert(
            abi.encodeWithSelector(UnexpectedMigrationLine.selector, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5)
        );
        schedule.run();

        SafeTx[] memory tokenRecord = new SafeTx[](1);
        tokenRecord[0] = LibStoxMigrations.recordTx(createZerogTokensDeclaration());
        QueueEntry[] memory entries = new QueueEntry[](1);
        entries[0] = entry(LibSafeTx.multiSendTx(tokenRecord), live);
        vm.setEnv("SAFE_QUEUE", writeQueue("create-zerog-tokens", queueFile(entries)));
        schedule.setUp();

        assertEq(safe.nonce(), live + 1, "queued record executed");
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.CREATE_ZEROG_TOKENS, "line at the token creation");

        SafeTx[] memory scheduleRecord = new SafeTx[](1);
        scheduleRecord[0] = LibStoxMigrations.recordTx(scheduleZerogOrchestratorRolesDeclaration());
        bytes32 authored = schedule.run();

        assertEq(authored, hashOf(LibSafeTx.multiSendTx(scheduleRecord), live + 1), "authored at the next nonce");
        assertEq(safe.nonce(), live + 2, "schedule executed on top");
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES, "line at the schedule");
    }

    function transferTx() internal pure returns (SafeTx memory) {
        return SafeTx({to: recipient(), value: TRANSFER_VALUE, data: hex"c0ffee", operation: Enum.Operation.Call});
    }

    function twoRecords(uint256 live) internal view returns (QueueEntry[] memory) {
        QueueEntry[] memory entries = new QueueEntry[](2);
        entries[0] = entry(LibStoxMigrations.recordTx(createZerogTokensDeclaration()), live);
        entries[1] = entry(LibStoxMigrations.recordTx(scheduleZerogOrchestratorRolesDeclaration()), live + 1);
        return entries;
    }

    function tampered(SafeTx memory txn, uint256 field) internal pure returns (SafeTx memory) {
        SafeTx memory changed = SafeTx({to: txn.to, value: txn.value, data: txn.data, operation: txn.operation});
        if (field == 0) changed.to = address(0xdead);
        if (field == 1) changed.value = txn.value + 1;
        if (field == 2) changed.data = bytes.concat(txn.data, hex"00");
        if (field == 3) changed.operation = Enum.Operation.DelegateCall;
        return changed;
    }

    function hashOf(SafeTx memory txn, uint256 nonce) internal view returns (bytes32) {
        return ethereumSafe()
            .getTransactionHash(txn.to, txn.value, txn.data, txn.operation, 0, 0, 0, address(0), address(0), nonce);
    }

    function entry(SafeTx memory txn, uint256 nonce) internal view returns (QueueEntry memory) {
        return QueueEntry({txn: txn, nonce: nonce, safeTxHash: hashOf(txn, nonce)});
    }

    function quoted(string memory raw) internal pure returns (string memory) {
        return string.concat("\"", raw, "\"");
    }

    function queueFile(QueueEntry[] memory entries) internal pure returns (QueueFile memory) {
        QueueFile memory file = QueueFile({
            to: new string[](entries.length),
            value: new string[](entries.length),
            data: new string[](entries.length),
            operation: new string[](entries.length),
            nonce: new string[](entries.length),
            safeTxHash: new string[](entries.length)
        });
        for (uint256 i = 0; i < entries.length; i++) {
            file.to[i] = quoted(vm.toString(entries[i].txn.to));
            file.value[i] = quoted(vm.toString(entries[i].txn.value));
            file.data[i] = quoted(vm.toString(entries[i].txn.data));
            file.operation[i] = vm.toString(uint256(entries[i].txn.operation));
            file.nonce[i] = vm.toString(entries[i].nonce);
            file.safeTxHash[i] = quoted(vm.toString(entries[i].safeTxHash));
        }
        return file;
    }

    function withExtra(string[] memory items) internal pure returns (string[] memory) {
        string[] memory longer = new string[](items.length + 1);
        for (uint256 i = 0; i < items.length; i++) {
            longer[i] = items[i];
        }
        longer[items.length] = items[0];
        return longer;
    }

    function withExtraEntry(QueueFile memory file, uint256 field) internal pure returns (QueueFile memory) {
        if (field == 0) file.to = withExtra(file.to);
        if (field == 1) file.value = withExtra(file.value);
        if (field == 2) file.data = withExtra(file.data);
        if (field == 3) file.operation = withExtra(file.operation);
        if (field == 4) file.nonce = withExtra(file.nonce);
        if (field == 5) file.safeTxHash = withExtra(file.safeTxHash);
        return file;
    }

    function jsonArray(string[] memory items) internal pure returns (string memory) {
        string memory json = "[";
        for (uint256 i = 0; i < items.length; i++) {
            if (i > 0) json = string.concat(json, ",");
            json = string.concat(json, items[i]);
        }
        return string.concat(json, "]");
    }

    function writeQueue(string memory name, QueueFile memory file) internal returns (string memory) {
        string memory path = string.concat("out/stox-safe-bundle-script-", name, ".json");
        vm.writeFile(
            path,
            string.concat(
                "{\"to\":",
                jsonArray(file.to),
                ",\"value\":",
                jsonArray(file.value),
                ",\"data\":",
                jsonArray(file.data),
                ",\"operation\":",
                jsonArray(file.operation),
                ",\"nonce\":",
                jsonArray(file.nonce),
                ",\"safeTxHash\":",
                jsonArray(file.safeTxHash),
                "}"
            )
        );
        return path;
    }
}
