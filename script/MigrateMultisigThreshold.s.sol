// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibProdSafes} from "../src/lib/LibProdSafes.sol";
import {LibInvariants} from "../src/lib/LibInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";

/// @notice A previously emitted Tx Builder JSON artifact (parsed via
/// `LibSafeOps.parseTxBuilderJson`) does not match the bundle the live
/// pre-flight would emit. Surfaces the first field that drifts, so a
/// signer can pinpoint where the off-chain artifact diverged from the
/// on-chain state at verification time.
/// @param field The name of the field that drifted (e.g. `"chainId"`,
/// `"to"`, `"data"`, `"safeTxHash"`).
error VerifyMismatch(string field);

/// @notice The verify pre-flight got a non-1 tx count from the artifact.
/// The threshold migration is a single-tx bundle; a multi-tx artifact at
/// this path is unambiguous drift rather than a future-proofing exercise.
/// @param actualCount The number of transactions in the parsed artifact.
error VerifyExpectedSingleTx(uint256 actualCount);

/// @title MigrateMultisigThreshold
/// @notice Forge script that authors the ST0x token-owner Safe's
/// multisig threshold migration (1-of-6 -> 3-of-6 against the post-rotation roster). Performs an
/// exhaustive on-chain pre-flight via `LibInvariants.assertAll`
/// (proxy codehash, singleton + bytecode, version, modules, guard,
/// fallback handler, uniform vault ownership, expected owner set,
/// expected threshold), simulates the post-state, emits a Safe Tx
/// Builder JSON artifact to `out/`, and logs the canonical `SafeTxHash`
/// that owners must sign.
/// @dev Two entrypoints:
/// - `run()`: dry-run against the active fork (typically a Base head
///   fork). Asserts every invariant the live execution will rely on,
///   simulates the inner call, and writes the Tx Builder artifact.
/// - `verify(jsonPath)`: re-runs the same pre-flight, parses an existing
///   artifact, and asserts the parsed artifact matches what the live
///   pre-flight would emit. Used by signers (or CI) to confirm an
///   artifact wasn't tampered with between authoring and signing.
///
/// Pre-flight uses the no-arg `assertAll(safe)` overload, which defaults
/// the expected threshold and owner set to the `LibProdSafes`-pinned
/// current truth. Post-state uses the full-args overload to override
/// the threshold with the deliberately-changed `TARGET_THRESHOLD`
/// while keeping the owner set pinned.
contract MigrateMultisigThreshold is Script {
    /// @notice Target signature threshold post-migration. Hardcoded literal
    /// (not derived from any constant) because the migration is a
    /// one-shot: encoding `3` as `THRESHOLD_PRE + 2` or similar would
    /// invite the "what if the pre-state changes" failure mode the script
    /// is meant to surface.
    uint256 internal constant TARGET_THRESHOLD = 3;

    /// @notice Human-readable name embedded in the emitted Tx Builder
    /// JSON's `meta.name`. Visible to signers in the Safe Tx Builder UI.
    string internal constant BUNDLE_NAME = "ST0x Safe threshold 1->3 (post-rotation roster)";

    /// @notice Output path (relative to the project root) for the Tx
    /// Builder JSON artifact. Picked up by the multisig-artifact GH
    /// workflow so PRs that touch the migration code expose the bundle
    /// as an artifact for review.
    string internal constant ARTIFACT_PATH = "out/safe-threshold-migration.json";

    /// @notice Dry-run the threshold migration: pre-flight every invariant
    /// via `assertAll`, simulate the post-state, emit the Tx Builder
    /// JSON artifact, and log the canonical SafeTxHash. Does not broadcast
    /// anything — the inner call is gated behind the Safe's own signature
    /// verification in production and we explicitly simulate via
    /// `vm.prank`.
    function run() external {
        IGnosisSafe safe = IGnosisSafe(LibProdSafes.STOX_TOKEN_OWNER_SAFE);
        // Pre-flight: every immutable invariant plus the pinned 6-owner
        // roster plus the pinned current threshold. Defaults from
        // `LibProdSafes` (no-arg overload). Reverts with the relevant
        // typed error from the underlying library on first mismatch.
        LibInvariants.assertAll(safe);

        // Build the single-tx bundle: a self-call to `changeThreshold(3)`.
        SafeTx memory txn = SafeTx({
            to: address(safe),
            value: 0,
            data: abi.encodeCall(IGnosisSafe.changeThreshold, (TARGET_THRESHOLD)),
            operation: 0
        });

        // Capture the nonce before any simulation. `simulateSelfCall`
        // doesn't advance the nonce, so the hash binds correctly to the
        // current Safe state.
        uint256 nonce = safe.nonce();
        bytes32 safeTxHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txn, nonce);

        // Simulate the inner call and re-assert post-state via the
        // full-args bundle. Overrides only the threshold (the
        // deliberately-changed value) while keeping the owner set on its
        // pinned current truth. If anything about the Safe rejects the
        // changeThreshold(3) call in production, it would also reject it
        // here (modulo the signature check, which `vm.prank` bypasses).
        // The bundle re-check guards against a `changeThreshold`
        // implementation that secretly mutates the owner roster, modules,
        // or fallback handler as a side effect.
        LibSafeOps.simulateSelfCall(safe, txn.data);
        LibInvariants.assertAll(safe, TARGET_THRESHOLD, LibProdSafes.expectedOwners());

        // Emit the Tx Builder JSON artifact and write it under `out/`.
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = txn;
        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, BUNDLE_NAME, txs);
        vm.writeFile(ARTIFACT_PATH, json);

        // Log the artifact with explicit BEGIN/END markers so CI can
        // grep the bundle from the run log even when the JSON has been
        // pretty-printed by an intermediate tool.
        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("SafeTxHash:", vm.toString(safeTxHash));
        console2.log("Nonce:", nonce);

        // n+1 reversibility check: prove the new state is not a dead end.
        // Builds the inverse `changeThreshold(STOX_TOKEN_OWNER_SAFE_THRESHOLD)`
        // as a follow-up tx; asserts undersigned attempts revert with
        // `GS020` and that `TARGET_THRESHOLD`-many sigs successfully roll
        // the threshold back. Per DevOps convention every critical state
        // change ships with the proof that it isn't terminal — DM's "ppl
        // put things in a state that cant be moved out of" framing.
        //
        // Sequenced AFTER the JSON emission so the artifact reflects the
        // forward migration (`changeThreshold(3)`) rather than the
        // reversal. The reversal exists only as a fork-local simulation;
        // signers never see it.
        LibSafeOps.simulateNPlus1Reversal(safe, LibProdSafes.STOX_TOKEN_OWNER_SAFE_THRESHOLD, TARGET_THRESHOLD);
        console2.log("n+1 reversibility check passed: threshold reverted to", safe.getThreshold());
    }

    /// @notice Re-runs the threshold migration pre-flight and asserts that
    /// a pre-emitted Tx Builder JSON at `jsonPath` matches what the live
    /// pre-flight would emit. Used by signers to confirm an artifact's
    /// integrity before signing.
    /// @param jsonPath Filesystem path to the Tx Builder JSON to verify.
    function verify(string calldata jsonPath) external view {
        IGnosisSafe safe = IGnosisSafe(LibProdSafes.STOX_TOKEN_OWNER_SAFE);
        // Same pre-flight bundle as `run()`. If the live state has drifted
        // since the artifact was authored, the typed error bubbles before
        // we even open the file.
        LibInvariants.assertAll(safe);

        (uint256 parsedChainId, address parsedSafe, SafeTx[] memory parsedTxs) = LibSafeOps.parseTxBuilderJson(jsonPath);

        if (parsedChainId != block.chainid) revert VerifyMismatch("chainId");
        if (parsedSafe != address(safe)) revert VerifyMismatch("safeAddress");
        if (parsedTxs.length != 1) revert VerifyExpectedSingleTx(parsedTxs.length);

        SafeTx memory expected = SafeTx({
            to: address(safe),
            value: 0,
            data: abi.encodeCall(IGnosisSafe.changeThreshold, (TARGET_THRESHOLD)),
            operation: 0
        });

        if (parsedTxs[0].to != expected.to) revert VerifyMismatch("to");
        if (parsedTxs[0].value != expected.value) revert VerifyMismatch("value");
        if (keccak256(parsedTxs[0].data) != keccak256(expected.data)) revert VerifyMismatch("data");

        // Cross-check the artifact's implied SafeTxHash against the live
        // Safe's hash builder using the current on-chain nonce. Drift here
        // is the strongest signal that the artifact is stale: a nonce bump
        // (some other Safe tx executed in between) will cause this to
        // flag, which is the desired safety property.
        bytes32 liveHash = LibSafeOps.computeSafeTxHashViaSafe(safe, expected, safe.nonce());
        bytes32 artifactHash = LibSafeOps.computeSafeTxHashViaSafe(safe, parsedTxs[0], safe.nonce());
        if (liveHash != artifactHash) revert VerifyMismatch("safeTxHash");
    }
}
