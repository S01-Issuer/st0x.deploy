// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibSafeOps, SafeTx, TxBuilderJsonNoTransactions} from "../../../src/lib/LibSafeOps.sol";
import {LibProdSafes} from "../../../src/lib/LibProdSafes.sol";
import {IGnosisSafe} from "../../../src/interface/IGnosisSafe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.2/src/lib/LibRainDeploy.sol";

/// @title LibSafeOpsTest
/// @notice Live fork tests for `LibSafeOps`: cross-checks the local hash
/// helper against the Safe's own `getTransactionHash`, asserts that the
/// `simulateSelfCall` helper applies the inner call without advancing the
/// nonce, and round-trips the Safe Tx Builder JSON serialise/parse pair.
contract LibSafeOpsTest is Test {
    /// @notice Live Safe handle reset by each test's `selectBaseFork`.
    IGnosisSafe internal safe;

    /// @notice Selects the Base fork at chain head — deliberately unpinned.
    /// Mirrors `LibProdSafes.t.sol::selectBaseFork` and
    /// `StoxProdV2.t.sol::testProdDeployBaseV2`: any drift in the live Safe
    /// surfaces immediately on the next CI run.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        safe = IGnosisSafe(LibProdSafes.STOX_TOKEN_OWNER_SAFE);
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
        assertEq(thresholdBefore, LibProdSafes.STOX_TOKEN_OWNER_SAFE_THRESHOLD_PRE_MIGRATION);

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
}

/// @notice Stub contract used by `testSimulateExternalCallPrankRoutes` to
/// capture the caller address of an external call. Kept inline because it
/// is single-use and trivially small.
contract CallerRecorder {
    /// @notice The most recent `msg.sender` to call `ping`.
    address public lastCaller;

    /// @notice Records the caller address. No return value; the recording
    /// is the side effect under test.
    function ping() external {
        lastCaller = msg.sender;
    }
}

/// @notice External-call harness around `LibSafeOps.parseTxBuilderJson` so
/// `vm.expectRevert` can catch the typed error. `expectRevert` only sees
/// reverts that bubble from a lower call depth than the cheatcode itself,
/// and library-internal reverts inline.
contract ParseHarness {
    function callParse(string calldata jsonPath) external view {
        LibSafeOps.parseTxBuilderJson(jsonPath);
    }
}
