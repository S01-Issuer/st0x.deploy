// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    MigrateMultisigThreshold,
    VerifyMismatch,
    VerifyExpectedSingleTx
} from "../../script/MigrateMultisigThreshold.s.sol";
import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../../src/lib/LibSafeOps.sol";
import {LibSafeInvariants, SafeThresholdMismatch} from "../../src/lib/LibSafeInvariants.sol";
import {IOwnable, ReceiptVaultOwnerMismatch} from "../../src/lib/LibTokenInvariants.sol";
import {LibTokenInvariants} from "../../src/lib/LibTokenInvariants.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";

/// @title MigrateMultisigThresholdTest
/// @notice End-to-end fork tests for the multisig threshold migration
/// script. Covers the happy-path `run()` dry-run, inverted preconditions
/// (each pre-flight invariant is exercised by mocking a single drift in
/// isolation), and the `run()` -> `verify()` chain (i.e. `verify` accepts
/// what `run` emits).
contract MigrateMultisigThresholdTest is Test {
    /// @notice The script under test, deployed fresh per fork.
    MigrateMultisigThreshold internal script;

    /// @notice Live Safe handle.
    IGnosisSafe internal safe;

    /// @notice Selects the Base fork at chain head — deliberately
    /// unpinned. Same precedent as
    /// `StoxProdV2.t.sol::testProdDeployBaseV2`.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        script = new MigrateMultisigThreshold();
        safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
    }

    /// @notice `run()` dry-run completes against the live pre-state,
    /// writes the artifact, and the artifact has the expected single-tx
    /// shape. The final fork state must show the threshold back at the
    /// pinned pre-migration value — this is the n+1 reversibility check's
    /// observable side effect: the script ends with the safe rolled back,
    /// proving the new state is exitable.
    function testRunCompletesAndWritesArtifact() external {
        selectBaseFork();
        script.run();

        // The artifact path the script writes to is project-relative,
        // resolved against `vm.projectRoot()`.
        string memory artifactPath = string.concat(vm.projectRoot(), "/out/safe-threshold-migration.json");
        string memory json = vm.readFile(artifactPath);

        // Smoke-check the JSON shape.
        string memory bundleName = vm.parseJsonString(json, ".meta.name");
        assertEq(bundleName, "ST0x Safe threshold 1->3 (post-rotation roster)", "meta.name pinned");
        bool hasFirstTx = vm.keyExistsJson(json, ".transactions[0].to");
        bool hasSecondTx = vm.keyExistsJson(json, ".transactions[1].to");
        assertTrue(hasFirstTx, "first transaction present");
        assertFalse(hasSecondTx, "exactly one transaction emitted");

        // After `run()` the n+1 reversibility check has rolled the
        // threshold back to its pre-migration value. Asserting the final
        // fork state matches the pinned pre-migration threshold is the
        // observable evidence that the reversal path executed
        // successfully — without it we'd be relying solely on the absence
        // of an internal revert.
        assertEq(
            safe.getThreshold(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
            "n+1 reversibility check rolled threshold back to pre-migration value"
        );
    }

    /// @notice `verify()` accepts the artifact emitted by `run()`. This
    /// is the load-bearing round-trip property — a signer should be able
    /// to take the artifact, run `verify` against the same fork, and get
    /// silent success.
    function testVerifyAcceptsRunArtifact() external {
        selectBaseFork();
        // `run()` simulates the inner call via `vm.prank`, which mutates
        // the Safe's threshold on the active fork. Snapshot first so we
        // can roll the fork back to the pre-run state and `verify()` sees
        // the same pinned current threshold it would see in production.
        uint256 snapshot = vm.snapshotState();
        script.run();
        string memory artifactPath = string.concat(vm.projectRoot(), "/out/safe-threshold-migration.json");
        vm.revertToState(snapshot);
        script.verify(artifactPath);
    }

    /// @notice Inverted: the pre-flight rejects a drifted threshold. If
    /// the Safe's threshold already moved off `1` (e.g. someone else ran
    /// a migration first), `run()` must trip the threshold invariant
    /// rather than emitting a stale artifact.
    function testRunRejectsAlreadyMigratedThreshold() external {
        selectBaseFork();
        // Mock the Safe's threshold to `3` to simulate post-migration
        // pre-state; the pre-flight should reject this.
        vm.mockCall(address(safe), abi.encodeWithSelector(IGnosisSafe.getThreshold.selector), abi.encode(uint256(3)));

        vm.expectRevert(abi.encodeWithSelector(SafeThresholdMismatch.selector, address(safe), uint256(1), uint256(3)));
        script.run();
    }

    /// @notice Inverted: the pre-flight rejects vault-ownership drift.
    /// If even one receipt vault has its `owner()` pointing somewhere
    /// other than the Safe, the migration must abort before producing an
    /// artifact (the migration would otherwise lock the wrong Safe into
    /// 3-of-6 without controlling the vaults).
    function testRunRejectsVaultOwnershipDrift() external {
        selectBaseFork();
        address rogueOwner = address(0xBADC0DE);
        // Victim address sourced from `LibTokenInvariants` — the canonical
        // list of production receipt vaults. Any vault from the list
        // would do; MSTR is the first entry.
        address victim = LibTokenInvariants.MSTR_RECEIPT_VAULT;
        vm.mockCall(victim, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(rogueOwner));

        vm.expectRevert(abi.encodeWithSelector(ReceiptVaultOwnerMismatch.selector, victim, address(safe), rogueOwner));
        script.run();
    }

    /// @notice Inverted: `verify()` rejects an artifact with a wrong
    /// `chainId`. We forge a minimal JSON with a bogus chain id and
    /// assert the typed `VerifyMismatch("chainId")` revert.
    function testVerifyRejectsWrongChainId() external {
        selectBaseFork();
        // Build a minimal-shape Tx Builder JSON with a deliberately-wrong
        // chainId. Tx Builder schema serialises `chainId` as a decimal
        // string.
        SafeTx memory txn = SafeTx({
            to: address(safe), value: 0, data: abi.encodeCall(IGnosisSafe.changeThreshold, (uint256(3))), operation: 0
        });
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = txn;
        // Emit a bundle that claims to be for a different chain id by
        // bypassing the live `block.chainid` and passing `block.chainid + 1`.
        string memory json =
            LibSafeOps.emitTxBuilderJson(address(safe), block.chainid + 1, "safe-verify-wrong-chain", txs);
        string memory path = string.concat(vm.projectRoot(), "/out/safe-verify-wrong-chain.json");
        vm.writeFile(path, json);

        vm.expectRevert(abi.encodeWithSelector(VerifyMismatch.selector, "chainId"));
        script.verify(path);
    }

    /// @notice Inverted: `verify()` rejects an artifact whose first tx
    /// targets a different Safe.
    function testVerifyRejectsWrongSafeAddress() external {
        selectBaseFork();
        address impostor = address(0xCAFEBABE);
        SafeTx memory txn = SafeTx({
            to: impostor, value: 0, data: abi.encodeCall(IGnosisSafe.changeThreshold, (uint256(3))), operation: 0
        });
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = txn;
        string memory json = LibSafeOps.emitTxBuilderJson(impostor, block.chainid, "safe-verify-wrong-safe", txs);
        string memory path = string.concat(vm.projectRoot(), "/out/safe-verify-wrong-safe.json");
        vm.writeFile(path, json);

        vm.expectRevert(abi.encodeWithSelector(VerifyMismatch.selector, "safeAddress"));
        script.verify(path);
    }

    /// @notice Inverted: `verify()` rejects an artifact whose tx
    /// calldata encodes a different threshold.
    function testVerifyRejectsWrongThresholdData() external {
        selectBaseFork();
        SafeTx memory txn = SafeTx({
            to: address(safe), value: 0, data: abi.encodeCall(IGnosisSafe.changeThreshold, (uint256(4))), operation: 0
        });
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = txn;
        string memory json =
            LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, "safe-verify-wrong-threshold", txs);
        string memory path = string.concat(vm.projectRoot(), "/out/safe-verify-wrong-threshold.json");
        vm.writeFile(path, json);

        vm.expectRevert(abi.encodeWithSelector(VerifyMismatch.selector, "data"));
        script.verify(path);
    }
}
