// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    LibSafeOps,
    SafeTx,
    TxBuilderJsonNoTransactions,
    TxBuilderJsonUnsupportedOperation
} from "../../../src/lib/LibSafeOps.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {IGnosisSafe} from "../../../src/interface/IGnosisSafe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {CallerRecorder} from "./CallerRecorder.sol";
import {ParseHarness} from "./ParseHarness.sol";
import {EmitHarness} from "./EmitHarness.sol";
import {NPlus1Harness} from "./NPlus1Harness.sol";
import {PackHarness} from "./PackHarness.sol";

/// @title LibSafeOpsTest
/// @notice Live fork tests for `LibSafeOps`: cross-checks the local hash
/// helper against the Safe's own `getTransactionHash`, asserts that the
/// `simulateSelfCall` helper applies the inner call without advancing the
/// nonce, and round-trips the Safe Tx Builder JSON serialise/parse pair.
contract LibSafeOpsTest is Test {
    /// @notice Live Safe handle reset by each test's `selectBaseFork`.
    IGnosisSafe internal safe;

    /// @notice Selects the Base fork at chain head — deliberately unpinned.
    /// Mirrors `LibSafeInvariants.t.sol::selectBaseFork` and
    /// `StoxProdV2.t.sol::testProdDeployBaseV2`: any drift in the live Safe
    /// surfaces immediately on the next CI run.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
    }

    /// @notice Build a single-tx bundle that changes the Safe's threshold
    /// to `3`. Used by every test that needs a representative `SafeTx`.
    function _buildThresholdTx() internal view returns (SafeTx memory) {
        return SafeTx({
            to: address(safe), value: 0, data: abi.encodeCall(IGnosisSafe.changeThreshold, (uint256(3))), operation: 0
        });
    }

    /// @notice `computeSafeTxHashViaSafe` returns the exact same hash the
    /// live Safe returns when called with the same parameters. This is the
    /// load-bearing assertion of the helper — if it ever returns a different
    /// hash than `safe.getTransactionHash` we'd be asking owners to sign a
    /// hash that doesn't match the on-chain verifier.
    function testHashMatchesLiveSafe() external {
        selectBaseFork();
        SafeTx memory txn = _buildThresholdTx();
        uint256 nonce = safe.nonce();

        bytes32 helperHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txn, nonce);
        bytes32 directHash =
            safe.getTransactionHash(txn.to, txn.value, txn.data, txn.operation, 0, 0, 0, address(0), address(0), nonce);

        assertEq(helperHash, directHash, "hash drift between helper and live Safe");
    }

    /// @notice `simulateSelfCall` applies the inner call against the
    /// Safe's storage (threshold flips to 3) but does NOT advance the
    /// Safe's nonce. The nonce is only advanced by a full `execTransaction`
    /// path; we want the simulated post-state, not a nonce burn.
    function testSimulateSelfCallChangesThresholdButNotNonce() external {
        selectBaseFork();
        uint256 nonceBefore = safe.nonce();
        uint256 thresholdBefore = safe.getThreshold();
        assertEq(thresholdBefore, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        SafeTx memory txn = _buildThresholdTx();
        LibSafeOps.simulateSelfCall(safe, txn.data);

        assertEq(safe.getThreshold(), 3, "post-simulation threshold should be 3");
        assertEq(safe.nonce(), nonceBefore, "nonce must not advance under simulation");
    }

    /// @notice `simulateExternalCall` prank-routes a call to an arbitrary
    /// target as if from the Safe. We mock a target that records its
    /// caller and assert the recorded caller is the Safe.
    function testSimulateExternalCallPrankRoutes() external {
        selectBaseFork();
        CallerRecorder recorder = new CallerRecorder();
        bytes memory pingData = abi.encodeCall(CallerRecorder.ping, ());
        LibSafeOps.simulateExternalCall(safe, address(recorder), pingData);
        assertEq(recorder.lastCaller(), address(safe), "external call must originate from the Safe");
    }

    /// @notice The JSON round-trip (`emit` then `parse`) yields a
    /// transactions array structurally identical to the input, with the
    /// chain id and target Safe preserved. Round-tripping is the load-
    /// bearing property here because the signers ingest the emitted JSON
    /// directly via the Tx Builder UI.
    function testEmitParseRoundtrip() external {
        selectBaseFork();
        SafeTx memory txn = _buildThresholdTx();
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = txn;

        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, "safe-threshold-test", txs);

        // Write the emitted JSON through forge's writeFile cheatcode then
        // re-read via parseTxBuilderJson. The on-disk hop ensures we
        // exercise the same path the script uses (write-to-artifact +
        // verify-from-artifact).
        string memory path = string.concat(vm.projectRoot(), "/out/test-tx-builder.json");
        vm.writeFile(path, json);

        (uint256 parsedChainId, address parsedSafe, SafeTx[] memory parsedTxs) = LibSafeOps.parseTxBuilderJson(path);

        assertEq(parsedChainId, block.chainid, "chain id should round-trip");
        assertEq(parsedSafe, address(safe), "target Safe should round-trip");
        assertEq(parsedTxs.length, txs.length, "tx count should round-trip");
        assertEq(parsedTxs[0].to, txn.to, "to should round-trip");
        assertEq(parsedTxs[0].value, txn.value, "value should round-trip");
        assertEq(parsedTxs[0].data, txn.data, "data should round-trip");
    }

    /// @notice The emitted JSON shape includes the expected top-level keys
    /// (`version`, `chainId`, `createdAt`, `meta`, `transactions`) and the
    /// pinned `meta.txBuilderVersion`. Asserted by re-parsing the JSON
    /// through forge cheatcodes — this is a fast structural check that
    /// catches accidental schema regressions before the signer UI does.
    function testEmittedJsonShape() external {
        selectBaseFork();
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = _buildThresholdTx();

        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, "safe-shape-test", txs);

        string memory schemaVersion = vm.parseJsonString(json, ".version");
        string memory txBuilderVersion = vm.parseJsonString(json, ".meta.txBuilderVersion");
        string memory bundleName = vm.parseJsonString(json, ".meta.name");
        // The transactions array is an array of objects; forge's wildcard
        // JSONPath returns the singular matched value for a single-element
        // array (not a 1-length array), so we probe by index via
        // `keyExistsJson` to count entries — the same trick the parser
        // uses.
        bool hasFirst = vm.keyExistsJson(json, ".transactions[0].to");
        bool hasSecond = vm.keyExistsJson(json, ".transactions[1].to");

        assertEq(schemaVersion, "1.0", "schema version pin");
        assertEq(txBuilderVersion, "1.16.5", "tx builder version pin");
        assertEq(bundleName, "safe-shape-test", "name pass-through");
        assertTrue(hasFirst, "transactions[0] should exist");
        assertFalse(hasSecond, "transactions[1] should not exist");
    }

    /// @notice `parseTxBuilderJson` reverts with `TxBuilderJsonNoTransactions`
    /// when the bundle's `transactions` array is empty. Empty bundles are
    /// never emitted by `emitTxBuilderJson`, so this is the structural
    /// minimum invariant for inbound JSON.
    function testParseRejectsEmptyTransactionsArray() external {
        selectBaseFork();
        // Hand-write a minimal-shape Tx Builder JSON with an empty array.
        string memory empty = string.concat(
            '{"version":"1.0","chainId":"',
            vm.toString(block.chainid),
            '","createdAt":0,"meta":{"name":"empty","txBuilderVersion":"1.16.5"},"transactions":[]}'
        );
        string memory path = string.concat(vm.projectRoot(), "/out/test-tx-builder-empty.json");
        vm.writeFile(path, empty);

        ParseHarness harness = new ParseHarness();
        vm.expectRevert(TxBuilderJsonNoTransactions.selector);
        harness.callParse(path);
    }

    /// @notice `emitTxBuilderJson` reverts on a non-CALL `operation` rather
    /// than silently dropping it. The Tx Builder schema has no `operation`
    /// field and `MultiSendCallOnly` is CALL-only, so a DELEGATECALL tx can't
    /// be faithfully represented — emitting it would produce an artifact that
    /// misdescribes how the bundle executes. The guard fires on the offending
    /// index, so the bundle's first (CALL) tx is accepted and the second
    /// (DELEGATECALL) one trips the revert.
    function testEmitRejectsNonCallOperation() external {
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({to: address(0xBEEF), value: 0, data: hex"deadbeef", operation: 0});
        txs[1] = SafeTx({to: address(0xCAFE), value: 0, data: hex"feed", operation: 1});

        EmitHarness harness = new EmitHarness();
        vm.expectRevert(abi.encodeWithSelector(TxBuilderJsonUnsupportedOperation.selector, uint256(1), uint8(1)));
        harness.callEmit(address(0x5AFE), 8453, "op-guard", txs);
    }

    /// @notice `simulateNPlus1Reversal` round-trips the Safe through a
    /// forward state change (`changeThreshold(3)`) and back. We first
    /// simulate the forward change via `vm.prank(safe) + changeThreshold(3)`
    /// — modelling what the migration script does post-`assertAll` — then
    /// invoke the helper with `(oldThreshold = 1, newThreshold = 3)`. The
    /// helper's internal `expectRevert(GS020)` exercises the threshold
    /// gate, and the successful `execTransaction` exercises the real
    /// signature-verification path end-to-end. Final state must be back at
    /// the pinned pre-migration threshold.
    function testSimulateNPlus1ReversalRoundTrip() external {
        selectBaseFork();
        uint256 oldThreshold = safe.getThreshold();
        assertEq(oldThreshold, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD, "pre-state threshold pin");

        // Simulate the forward state change the migration script makes.
        // After this prank-call the Safe is in the "post-migration" state
        // the helper is meant to prove is not stuck.
        uint256 newThreshold = 3;
        vm.prank(address(safe));
        safe.changeThreshold(newThreshold);
        assertEq(safe.getThreshold(), newThreshold, "post-forward-change threshold");

        LibSafeOps.simulateNPlus1Reversal(safe, oldThreshold, newThreshold);

        assertEq(safe.getThreshold(), oldThreshold, "threshold restored by n+1 reversal");
    }

    /// @notice `simulateNPlus1Reversal` reverts cleanly if the Safe's
    /// owner count is below `newThreshold`. The require message protects
    /// against a misuse where the helper is called with a threshold higher
    /// than the live roster can satisfy, which would otherwise blow up
    /// deep inside `approveHash`/`execTransaction` with a less-actionable
    /// error.
    function testSimulateNPlus1ReversalFailsWithTooFewOwners() external {
        selectBaseFork();
        // Mock the live Safe to expose only 2 owners, then ask the helper
        // for `newThreshold = 3`. The require in `simulateNPlus1Reversal`
        // should fire before any prank/approve hit the Safe.
        address[] memory shortRoster = new address[](2);
        shortRoster[0] = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_1;
        shortRoster[1] = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_2;
        vm.mockCall(address(safe), abi.encodeWithSelector(IGnosisSafe.getOwners.selector), abi.encode(shortRoster));

        NPlus1Harness harness = new NPlus1Harness();
        vm.expectRevert(bytes("LibSafeOps: not enough owners for n+1"));
        harness.callSimulateNPlus1Reversal(safe, 1, 3);
    }

    /// @notice `packApprovedHashSignatures` lays out 65-byte entries in the
    /// Safe v1.4.1 approved-hash format: `r = bytes32(address)`,
    /// `s = bytes32(0)`, `v = 0x01`. For three signers the blob is 195
    /// bytes; per-entry slices must round-trip back to the input addresses.
    function testPackApprovedHashSignatures() external pure {
        address[] memory signers = new address[](3);
        signers[0] = address(0x0000000000000000000000000000000000000001);
        signers[1] = address(0x1234567890123456789012345678901234567890);
        signers[2] = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

        bytes memory packed = LibSafeOps.packApprovedHashSignatures(signers, 3);
        assertEq(packed.length, 3 * 65, "65 bytes per approved-hash entry");

        // Walk the blob: every entry has its r-field at offset i*65, the
        // s-field zeroed at offset i*65 + 32, and v=0x01 at offset i*65 + 64.
        for (uint256 i = 0; i < 3; i++) {
            uint256 entryStart = i * 65;
            bytes32 rWord;
            bytes32 sWord;
            uint8 vByte;
            for (uint256 b = 0; b < 32; b++) {
                rWord |= bytes32(uint256(uint8(packed[entryStart + b])) << ((31 - b) * 8));
                sWord |= bytes32(uint256(uint8(packed[entryStart + 32 + b])) << ((31 - b) * 8));
            }
            vByte = uint8(packed[entryStart + 64]);
            assertEq(address(uint160(uint256(rWord))), signers[i], "r decodes to signer address");
            assertEq(sWord, bytes32(0), "s is zeroed");
            assertEq(vByte, uint8(0x01), "v is the approved-hash marker");
        }
    }

    /// @notice `packApprovedHashSignatures` truncates the output to `count`
    /// entries when `count < sortedSigners.length`. Used by the negative
    /// branch of `simulateNPlus1Reversal` to feed `execTransaction` a
    /// deliberately-undersigned blob without reallocating the source array.
    function testPackApprovedHashSignaturesPartialCount() external pure {
        address[] memory signers = new address[](3);
        signers[0] = address(0x1);
        signers[1] = address(0x2);
        signers[2] = address(0x3);

        bytes memory packed = LibSafeOps.packApprovedHashSignatures(signers, 2);
        assertEq(packed.length, 2 * 65, "truncated to 2 entries");
    }

    /// @notice `packApprovedHashSignatures` reverts if asked to pack more
    /// entries than the input contains. Prevents an out-of-bounds index
    /// read silently producing a partial blob.
    function testPackApprovedHashSignaturesRejectsOverflow() external {
        address[] memory signers = new address[](2);
        signers[0] = address(0x1);
        signers[1] = address(0x2);

        PackHarness harness = new PackHarness();
        vm.expectRevert(bytes("LibSafeOps: pack count exceeds signers"));
        harness.callPack(signers, 3);
    }

    /// @notice `sortAddressesAscending` returns a fresh array whose entries
    /// are the input addresses in strict ascending order. Verified against
    /// a hand-picked unsorted input (descending, with duplicates would only
    /// matter if Safe accepted them — which it doesn't — so distinct values
    /// suffice).
    function testSortAddressesAscending() external pure {
        address[] memory input = new address[](4);
        input[0] = address(0x000000000000000000000000000000000000bEEF);
        input[1] = address(0x000000000000000000000000000000000000cafE);
        input[2] = address(0x0000000000000000000000000000000000000001);
        input[3] = address(0x000000000000000000000000000000000000dEaD);

        address[] memory sorted = LibSafeOps.sortAddressesAscending(input);
        assertEq(sorted.length, input.length, "length preserved");
        for (uint256 i = 1; i < sorted.length; i++) {
            assertTrue(sorted[i - 1] < sorted[i], "strictly ascending");
        }
        // Spot-check the smallest and largest entries.
        assertEq(sorted[0], address(0x0000000000000000000000000000000000000001), "min at index 0");
        assertEq(sorted[3], address(0x000000000000000000000000000000000000dEaD), "max at last index");
    }
}

