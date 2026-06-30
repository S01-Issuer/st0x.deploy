// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibInvariants} from "../src/lib/LibInvariants.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";

/// @notice A previously emitted Tx Builder JSON artifact (parsed via
/// `LibSafeOps.parseTxBuilderJson`) does not match the bundle the live
/// pre-flight would emit. Surfaces the first field that drifts, so a signer
/// can pinpoint where the off-chain artifact diverged from on-chain state at
/// verification time.
/// @param field The name of the field that drifted (e.g. `"chainId"`, `"to"`,
/// `"data"`, `"safeTxHash"`).
error VerifyMismatch(string field);

/// @notice The verify pre-flight got a non-1 tx count from the artifact. Each
/// grant bundle is a single-tx bundle (DEPOSIT and WITHDRAW are authored as
/// two independent bundles because `LibSafeOps` hashes a single `SafeTx`, not
/// a MultiSend batch); a multi-tx artifact at this path is unambiguous drift.
/// @param actualCount The number of transactions in the parsed artifact.
error VerifyExpectedSingleTx(uint256 actualCount);

/// @notice The issuer already holds the role the bundle would grant. The
/// bundle is a one-shot onboarding step: if the grant is already live the
/// pre-state has drifted from what the bundle assumes, and authoring it would
/// emit a no-op that wastes a signing ceremony.
/// @param role The role the issuer already holds.
error IssuerAlreadyHoldsRole(bytes32 role);

/// @notice The simulated `grantRole` did not leave the issuer holding the
/// role. A defensive post-state assertion: if the authoriser's `grantRole`
/// silently no-ops (e.g. an unexpected impl behind the clone) this trips
/// before the artifact is trusted.
/// @param role The role that failed to apply.
error GrantNotApplied(bytes32 role);

/// @title GrantIssuerMintBurn
/// @notice **PENDING.** Authors the ST0x token-owner Safe bundles that grant
/// the new issuer EOA `0x3d0C…E8aE` the `DEPOSIT` (mint) and `WITHDRAW`
/// (burn) roles on the live shared authoriser. Because every production
/// receipt vault shares this one authoriser and its role checks are not
/// vault-scoped, the two grants enable the issuer to mint and burn across
/// every ST0x SFT at once. The pre-flight asserts that uniformity
/// (`LibInvariants.assertAll` runs `assertUniformAuthoriser`) so the "every
/// SFT" guarantee is proven against the live chain before a signer sees a
/// bundle.
/// @dev `DEPOSIT` and `WITHDRAW` are authored as **two single-tx bundles**,
/// not one batch: `LibSafeOps.computeSafeTxHashViaSafe` hashes a single
/// `SafeTx`, whereas the Safe Tx Builder UI MultiSends a multi-tx bundle into
/// one delegatecall and signs that — so a 2-tx bundle's per-tx hash would not
/// match what signers verify. The grants are independent (a half-applied
/// state is benign and revocable), so two bundles is the faithful shape.
///
/// Four entrypoints, two per role:
/// - `grantDeposit()` / `grantWithdraw()`: dry-run + emit Safe Tx Builder
///   JSON + log the canonical SafeTxHash. Each MUST run in its own `forge
///   script` process — the n+1 reversibility check advances the Safe nonce,
///   so chaining both in one process would compute the second artifact's hash
///   at the wrong nonce.
/// - `verifyDeposit(string)` / `verifyWithdraw(string)`: re-run the pre-flight
///   and assert an existing artifact matches what the live pre-flight emits.
contract GrantIssuerMintBurn is Script {
    /// @notice The new issuer EOA being granted mint + burn authority.
    /// Hardcoded literal: the bundle is a one-shot onboarding step for this
    /// specific operator, not a parameterised utility.
    /// https://basescan.org/address/0x3d0cd66efa66c05d86c3d4316b03eae87ab9e8ae
    address internal constant ISSUER = 0x3d0CD66EFA66c05d86c3d4316B03eAE87ab9E8aE;

    /// @notice The mint role on the OffchainAssetReceiptVault authoriser.
    /// `DEPOSIT` gates issuing (minting) shares + receipts. Derived the same
    /// way `LibAuthoriserInvariants.expectedGrants` derives it so the literals
    /// cannot drift apart.
    bytes32 internal constant DEPOSIT = keccak256("DEPOSIT");

    /// @notice The burn role on the authoriser. `WITHDRAW` gates redeeming
    /// (burning) shares + receipts.
    bytes32 internal constant WITHDRAW = keccak256("WITHDRAW");

    /// @notice Signer-visible `meta.name` for the DEPOSIT (mint) bundle.
    string internal constant DEPOSIT_BUNDLE_NAME = "ST0x authoriser - grant DEPOSIT (mint) to new issuer";

    /// @notice Signer-visible `meta.name` for the WITHDRAW (burn) bundle.
    string internal constant WITHDRAW_BUNDLE_NAME = "ST0x authoriser - grant WITHDRAW (burn) to new issuer";

    /// @notice Output path for the DEPOSIT (mint) grant bundle. `out/` is
    /// repo-wide read-write in `foundry.toml` `fs_permissions`.
    string internal constant DEPOSIT_ARTIFACT_PATH = "out/grant-issuer-deposit.json";

    /// @notice Output path for the WITHDRAW (burn) grant bundle.
    string internal constant WITHDRAW_ARTIFACT_PATH = "out/grant-issuer-withdraw.json";

    /// @notice Dry-run + author the DEPOSIT (mint) grant bundle.
    function grantDeposit() external {
        _authorGrant(DEPOSIT, DEPOSIT_BUNDLE_NAME, DEPOSIT_ARTIFACT_PATH);
    }

    /// @notice Dry-run + author the WITHDRAW (burn) grant bundle.
    function grantWithdraw() external {
        _authorGrant(WITHDRAW, WITHDRAW_BUNDLE_NAME, WITHDRAW_ARTIFACT_PATH);
    }

    /// @notice Verify a pre-emitted DEPOSIT (mint) grant artifact.
    /// @param jsonPath Filesystem path to the Tx Builder JSON to verify.
    function verifyDeposit(string calldata jsonPath) external view {
        _verifyGrant(DEPOSIT, jsonPath);
    }

    /// @notice Verify a pre-emitted WITHDRAW (burn) grant artifact.
    /// @param jsonPath Filesystem path to the Tx Builder JSON to verify.
    function verifyWithdraw(string calldata jsonPath) external view {
        _verifyGrant(WITHDRAW, jsonPath);
    }

    /// @notice Shared authoring path for a single role grant. Mirrors the
    /// `MigrateMultisigThreshold.run()` shape: pre-flight, build the inner tx,
    /// compute the canonical hash at the current nonce, simulate, re-assert
    /// post-state, emit the artifact, then prove the grant is reversible.
    /// @param role The role to grant the issuer.
    /// @param bundleName The signer-visible `meta.name`.
    /// @param artifactPath The `out/` path to write the bundle to.
    function _authorGrant(bytes32 role, string memory bundleName, string memory artifactPath) internal {
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        address authoriser = LibAuthoriserInvariants.STOX_PROD_AUTHORISER;

        // (1) Pre-flight. The orchestrator asserts Safe identity / config,
        // uniform vault ownership, uniform authoriser (every production
        // vault's `authorizer()` == STOX_PROD_AUTHORISER — the proof the
        // grant reaches every SFT), and the pinned authoriser role grants
        // (including the Safe holding `<ROLE>_ADMIN`, which is what lets the
        // Safe grant `role` at all).
        LibInvariants.assertAll(safe);

        // (1b) Idempotency guard: the bundle must change state. If the issuer
        // already holds the role the pre-state has drifted; abort rather than
        // author a no-op.
        if (IAccessControl(authoriser).hasRole(role, ISSUER)) revert IssuerAlreadyHoldsRole(role);

        // (2) Build the single-tx bundle: Safe -> authoriser.grantRole(role,
        // issuer). `abi.encodeCall` type-checks the selector + args.
        SafeTx memory txn = SafeTx({
            to: authoriser,
            value: 0,
            data: abi.encodeCall(IAccessControl.grantRole, (role, ISSUER)),
            operation: 0
        });

        // (3) Capture the nonce before any simulation. `simulateExternalCall`
        // does not advance the nonce, so the hash binds to the current Safe
        // state the signer will see.
        uint256 nonce = safe.nonce();
        bytes32 safeTxHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txn, nonce);

        // (4) Simulate the Safe-originated call into the authoriser, mutating
        // the fork to the post-grant state. The pre-flight already proved the
        // Safe holds `<ROLE>_ADMIN`, so this grant succeeds exactly as the
        // live `execTransaction` would.
        LibSafeOps.simulateExternalCall(safe, authoriser, txn.data);

        // (5) Post-state: the grant applied, and every pinned authoriser
        // invariant still holds (the new grant is additive — it removes
        // nothing the invariant pins).
        if (!IAccessControl(authoriser).hasRole(role, ISSUER)) revert GrantNotApplied(role);
        LibAuthoriserInvariants.assertAll();

        // (6) Emit the Tx Builder JSON and log it with greppable markers.
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = txn;
        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, bundleName, txs);
        vm.writeFile(artifactPath, json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("SafeTxHash:", vm.toString(safeTxHash));
        console2.log("Nonce:", nonce);

        // (7) n+1 reversibility: prove the grant is not a dead end by
        // executing the inverse `revokeRole(role, issuer)` under the live
        // threshold (and proving an undersigned attempt reverts GS020).
        // Sequenced AFTER the artifact emission so the bundle reflects the
        // forward grant; the revoke exists only as a fork-local simulation.
        LibSafeOps.simulateNPlus1(
            safe, authoriser, abi.encodeCall(IAccessControl.revokeRole, (role, ISSUER)), safe.getThreshold()
        );
        require(
            !IAccessControl(authoriser).hasRole(role, ISSUER),
            "GrantIssuerMintBurn: n+1 reversibility did not revoke the role"
        );
        console2.log("n+1 reversibility check passed: role revoked");
    }

    /// @notice Shared verify path. Re-runs the pre-flight, parses the
    /// artifact, and asserts every field matches what the live pre-flight
    /// would emit. Typed `VerifyMismatch(field)` on the first divergence.
    /// @param role The role the artifact is expected to grant.
    /// @param jsonPath Filesystem path to the Tx Builder JSON to verify.
    function _verifyGrant(bytes32 role, string memory jsonPath) internal view {
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        address authoriser = LibAuthoriserInvariants.STOX_PROD_AUTHORISER;

        // Same pre-flight as the authoring path. If the live state has drifted
        // since the artifact was authored, the typed error bubbles before we
        // open the file.
        LibInvariants.assertAll(safe);

        (uint256 parsedChainId, address parsedTarget, SafeTx[] memory parsedTxs) =
            LibSafeOps.parseTxBuilderJson(jsonPath);

        if (parsedChainId != block.chainid) revert VerifyMismatch("chainId");
        if (parsedTxs.length != 1) revert VerifyExpectedSingleTx(parsedTxs.length);
        // `parseTxBuilderJson` reports `parsedTarget` as `transactions[0].to`;
        // for a grant bundle that is the authoriser, not the Safe.
        if (parsedTarget != authoriser) revert VerifyMismatch("to");

        SafeTx memory expected = SafeTx({
            to: authoriser,
            value: 0,
            data: abi.encodeCall(IAccessControl.grantRole, (role, ISSUER)),
            operation: 0
        });

        if (parsedTxs[0].to != expected.to) revert VerifyMismatch("to");
        if (parsedTxs[0].value != expected.value) revert VerifyMismatch("value");
        if (keccak256(parsedTxs[0].data) != keccak256(expected.data)) revert VerifyMismatch("data");

        // Cross-check the artifact's implied SafeTxHash against the live Safe's
        // hash builder at the current nonce. A nonce bump (some other Safe tx
        // executed in between) flags here, which is the desired staleness
        // signal.
        bytes32 liveHash = LibSafeOps.computeSafeTxHashViaSafe(safe, expected, safe.nonce());
        bytes32 artifactHash = LibSafeOps.computeSafeTxHashViaSafe(safe, parsedTxs[0], safe.nonce());
        if (liveHash != artifactHash) revert VerifyMismatch("safeTxHash");
    }
}
