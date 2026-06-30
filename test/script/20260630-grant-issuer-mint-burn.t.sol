// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {
    GrantIssuerMintBurn,
    VerifyMismatch,
    VerifyExpectedSingleTx,
    IssuerAlreadyHoldsRole
} from "../../script/20260630-grant-issuer-mint-burn.s.sol";
import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {IAuthorisable} from "../../src/interface/IAuthorisable.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../../src/lib/LibSafeOps.sol";
import {LibAuthoriserInvariants, ExpectedGrantMissing} from "../../src/lib/LibAuthoriserInvariants.sol";
import {
    LibTokenInvariants,
    IOwnable,
    ReceiptVaultOwnerMismatch,
    ReceiptVaultAuthoriserMismatch
} from "../../src/lib/LibTokenInvariants.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title GrantIssuerMintBurnTest
/// @notice End-to-end fork tests for the issuer mint/burn grant script.
/// Covers the happy-path authoring of both single-tx grant bundles, the
/// `grant -> verify` round-trip, the inverted pre-flight invariants (each
/// mocked in isolation), and inverted `verify` rejections. Mirrors the
/// `MigrateMultisigThresholdTest` shape; per the runbook, domain-lib
/// invariants are exercised in their own lib test suites and only this
/// script's bundle-emitting + assertion logic is tested here.
contract GrantIssuerMintBurnTest is Test {
    /// @notice The script under test, deployed fresh per fork.
    GrantIssuerMintBurn internal script;

    /// @notice Live Safe handle.
    IGnosisSafe internal safe;

    /// @notice The live shared authoriser the grants target.
    address internal authoriser;

    /// @notice The issuer EOA being granted mint + burn. Mirrors the
    /// `GrantIssuerMintBurn.ISSUER` literal (internal constants aren't
    /// reachable from the test; kept in sync by hand).
    address internal constant ISSUER = 0x3d0CD66EFA66c05d86c3d4316B03eAE87ab9E8aE;

    /// @notice Mint role. Mirrors `GrantIssuerMintBurn.DEPOSIT`.
    bytes32 internal constant DEPOSIT = keccak256("DEPOSIT");

    /// @notice Burn role. Mirrors `GrantIssuerMintBurn.WITHDRAW`.
    bytes32 internal constant WITHDRAW = keccak256("WITHDRAW");

    /// @notice Selects the Base fork at chain head — deliberately unpinned,
    /// matching the live-drift-detector precedent in
    /// `MigrateMultisigThresholdTest`.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        script = new GrantIssuerMintBurn();
        safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        authoriser = LibAuthoriserInvariants.STOX_PROD_AUTHORISER;
    }

    /// @notice `grantDeposit()` dry-run completes against the live pre-state,
    /// writes the artifact with the pinned `meta.name` and exactly one tx,
    /// and ends with the issuer NOT holding the role — the observable side
    /// effect of the n+1 reversibility check having revoked the grant it
    /// simulated.
    function testGrantDepositCompletesAndWritesArtifact() external {
        selectBaseFork();
        script.grantDeposit();

        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/out/grant-issuer-deposit.json"));
        assertEq(
            vm.parseJsonString(json, ".meta.name"),
            "ST0x authoriser - grant DEPOSIT (mint) to new issuer",
            "meta.name pinned"
        );
        assertTrue(vm.keyExistsJson(json, ".transactions[0].to"), "first transaction present");
        assertFalse(vm.keyExistsJson(json, ".transactions[1].to"), "exactly one transaction emitted");

        assertFalse(
            IAccessControl(authoriser).hasRole(DEPOSIT, ISSUER), "n+1 reversibility revoked the simulated grant"
        );
    }

    /// @notice `grantWithdraw()` dry-run completes, writes the burn-grant
    /// artifact, and likewise ends with the role revoked.
    function testGrantWithdrawCompletesAndWritesArtifact() external {
        selectBaseFork();
        script.grantWithdraw();

        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/out/grant-issuer-withdraw.json"));
        assertEq(
            vm.parseJsonString(json, ".meta.name"),
            "ST0x authoriser - grant WITHDRAW (burn) to new issuer",
            "meta.name pinned"
        );
        assertTrue(vm.keyExistsJson(json, ".transactions[0].to"), "first transaction present");
        assertFalse(vm.keyExistsJson(json, ".transactions[1].to"), "exactly one transaction emitted");

        assertFalse(
            IAccessControl(authoriser).hasRole(WITHDRAW, ISSUER), "n+1 reversibility revoked the simulated grant"
        );
    }

    /// @notice `verifyDeposit()` accepts the artifact `grantDeposit()` emits.
    /// The load-bearing round-trip: snapshot, author, roll the fork back to
    /// the pre-run state, then verify against the artifact.
    function testVerifyAcceptsDepositArtifact() external {
        selectBaseFork();
        uint256 snapshot = vm.snapshotState();
        script.grantDeposit();
        vm.revertToState(snapshot);
        script.verifyDeposit(string.concat(vm.projectRoot(), "/out/grant-issuer-deposit.json"));
    }

    /// @notice `verifyWithdraw()` accepts the artifact `grantWithdraw()`
    /// emits.
    function testVerifyAcceptsWithdrawArtifact() external {
        selectBaseFork();
        uint256 snapshot = vm.snapshotState();
        script.grantWithdraw();
        vm.revertToState(snapshot);
        script.verifyWithdraw(string.concat(vm.projectRoot(), "/out/grant-issuer-withdraw.json"));
    }

    /// @notice Inverted: the idempotency guard rejects authoring a no-op. If
    /// the issuer already holds the role, the bundle would waste a signing
    /// ceremony, so `grantDeposit()` must abort. Mocks only the
    /// `hasRole(DEPOSIT, ISSUER)` pair so the pre-flight's other grant checks
    /// still read live truth.
    function testGrantDepositRejectsAlreadyGranted() external {
        selectBaseFork();
        vm.mockCall(
            authoriser, abi.encodeWithSelector(IAccessControl.hasRole.selector, DEPOSIT, ISSUER), abi.encode(true)
        );
        vm.expectRevert(abi.encodeWithSelector(IssuerAlreadyHoldsRole.selector, DEPOSIT));
        script.grantDeposit();
    }

    /// @notice Inverted: the pre-flight rejects authoriser grant drift. If a
    /// pinned `(role, grantee)` pair is missing — here the Safe's
    /// `DEPOSIT_ADMIN`, which is also what authorises the Safe to grant
    /// `DEPOSIT` at all — the bundle must abort before producing an artifact.
    function testGrantRejectsAuthoriserGrantDrift() external {
        selectBaseFork();
        bytes32 depositAdmin = keccak256("DEPOSIT_ADMIN");
        address safeGrantee = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        vm.mockCall(
            authoriser,
            abi.encodeWithSelector(IAccessControl.hasRole.selector, depositAdmin, safeGrantee),
            abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(ExpectedGrantMissing.selector, authoriser, depositAdmin, safeGrantee));
        script.grantDeposit();
    }

    /// @notice Inverted: the pre-flight rejects vault-ownership drift. If even
    /// one production receipt vault's `owner()` points off the Safe, the
    /// grant must abort (the authoriser would be gating a vault the Safe no
    /// longer controls).
    function testGrantRejectsVaultOwnershipDrift() external {
        selectBaseFork();
        address rogueOwner = address(0xBADC0DE);
        address victim = LibTokenInvariants.MSTR_RECEIPT_VAULT;
        vm.mockCall(victim, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(rogueOwner));
        vm.expectRevert(abi.encodeWithSelector(ReceiptVaultOwnerMismatch.selector, victim, address(safe), rogueOwner));
        script.grantDeposit();
    }

    /// @notice Inverted: the pre-flight rejects vault-authoriser drift. This
    /// is the load-bearing coverage property — if even one vault's
    /// `authorizer()` diverges from the target authoriser, the global grant
    /// would NOT reach that SFT, so the bundle must abort.
    function testGrantRejectsVaultAuthoriserDrift() external {
        selectBaseFork();
        address rogueAuthoriser = address(0xBADC0DE);
        address victim = LibTokenInvariants.MSTR_RECEIPT_VAULT;
        vm.mockCall(victim, abi.encodeWithSelector(IAuthorisable.authorizer.selector), abi.encode(rogueAuthoriser));
        vm.expectRevert(
            abi.encodeWithSelector(ReceiptVaultAuthoriserMismatch.selector, victim, authoriser, rogueAuthoriser)
        );
        script.grantDeposit();
    }

    /// @notice Inverted: `verifyDeposit()` rejects an artifact with a wrong
    /// `chainId`.
    function testVerifyRejectsWrongChainId() external {
        selectBaseFork();
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({
            to: authoriser,
            value: 0,
            data: abi.encodeCall(IAccessControl.grantRole, (DEPOSIT, ISSUER)),
            operation: 0
        });
        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid + 1, "grant-wrong-chain", txs);
        string memory path = string.concat(vm.projectRoot(), "/out/grant-wrong-chain.json");
        vm.writeFile(path, json);

        vm.expectRevert(abi.encodeWithSelector(VerifyMismatch.selector, "chainId"));
        script.verifyDeposit(path);
    }

    /// @notice Inverted: `verifyDeposit()` rejects an artifact that encodes a
    /// different role (here a WITHDRAW grant verified as a DEPOSIT grant).
    /// The calldata differs, so the `data` field check trips.
    function testVerifyRejectsWrongRoleData() external {
        selectBaseFork();
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({
            to: authoriser,
            value: 0,
            data: abi.encodeCall(IAccessControl.grantRole, (WITHDRAW, ISSUER)),
            operation: 0
        });
        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, "grant-wrong-role", txs);
        string memory path = string.concat(vm.projectRoot(), "/out/grant-wrong-role.json");
        vm.writeFile(path, json);

        vm.expectRevert(abi.encodeWithSelector(VerifyMismatch.selector, "data"));
        script.verifyDeposit(path);
    }

    /// @notice Inverted: `verifyDeposit()` rejects an artifact whose tx
    /// targets a different contract than the authoriser.
    function testVerifyRejectsWrongTarget() external {
        selectBaseFork();
        address impostor = address(0xCAFEBABE);
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({
            to: impostor,
            value: 0,
            data: abi.encodeCall(IAccessControl.grantRole, (DEPOSIT, ISSUER)),
            operation: 0
        });
        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, "grant-wrong-target", txs);
        string memory path = string.concat(vm.projectRoot(), "/out/grant-wrong-target.json");
        vm.writeFile(path, json);

        vm.expectRevert(abi.encodeWithSelector(VerifyMismatch.selector, "to"));
        script.verifyDeposit(path);
    }
}
