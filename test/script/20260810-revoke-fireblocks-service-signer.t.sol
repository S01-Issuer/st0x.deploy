// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {Clones} from "@openzeppelin-contracts-5.6.1/proxy/Clones.sol";
import {ICLONEABLE_V2_SUCCESS} from "rain-factory-0.1.1/src/interface/ICloneableV2.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {FireblocksSignerAlreadyRevoked} from "../../script/20260810-revoke-fireblocks-service-signer.s.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {SafeTx} from "../../src/lib/LibSafeOps.sol";
import {RevokeFireblocksServiceSignerHarness} from "./RevokeFireblocksServiceSignerHarness.sol";

/// @title RevokeFireblocksServiceSignerTest
/// @notice UNIT coverage for the retired-signer revocation SELECTION —
/// which canonical pairs the script authors for a given authoriser state,
/// and when it refuses to author at all.
///
/// No fork and no mocks. Every fixture is a real EIP-1167 clone of the real
/// `StoxOffchainAssetReceiptVaultAuthorizerV1`, driven into the state under
/// test by real `grantRole`/`revokeRole` calls made by the address holding
/// the role's `_ADMIN`. The role state is therefore produced by the same
/// code path production uses, and no assertion here can be invalidated by
/// anything signed on-chain.
///
/// The pairs come from `LibAuthoriserInvariants.expectedGrants()`, the
/// single current-state map every live invariant asserts, so the fixture
/// cannot drift from the map the script reads.
///
/// Live per-chain state is asserted separately, unmocked, in
/// `20260810-revoke-fireblocks-service-signer.prod.t.sol`.
contract RevokeFireblocksServiceSignerTest is Test {
    /// @notice The signer being revoked — the canonical pin the script
    /// scopes itself to.
    address internal constant SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_1C66;

    /// @notice Stand-in for a chain's token-owner Safe. The selection only
    /// needs an address that holds the `_ADMIN` roles and fills the map's
    /// Safe grantee slots; a locally cloned authoriser can be initialised
    /// with any such address, so no Safe bytecode is involved.
    address internal constant SAFE = address(uint160(uint256(keccak256("unit.token.owner.safe"))));

    bytes32 internal constant DEPOSIT = keccak256("DEPOSIT");
    bytes32 internal constant WITHDRAW = keccak256("WITHDRAW");
    bytes32 internal constant CERTIFY = keccak256("CERTIFY");

    /// @notice A locally cloned V4 authoriser carrying EVERY canonical row,
    /// the retired signer's three included — the pre-revocation state, i.e.
    /// the state the script was written against. `initialize` auto-grants
    /// `SAFE` the seven `_ADMIN` roles; the remaining rows are then granted
    /// by `SAFE` under those admins. The loop is driven by
    /// `expectedGrants()` itself, so a new canonical row lands in the
    /// fixture without editing it.
    /// @return authoriser The initialised clone.
    function deployFullyGrantedAuthoriser() internal returns (address authoriser) {
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        authoriser = Clones.clone(address(impl));
        assertEq(
            StoxOffchainAssetReceiptVaultAuthorizerV1(authoriser)
                .initialize(abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: SAFE}))),
            ICLONEABLE_V2_SUCCESS,
            "authoriser clone failed to initialise"
        );

        IAccessControl acl = IAccessControl(authoriser);
        RoleGrant[] memory all = LibAuthoriserInvariants.expectedGrants(SAFE);
        for (uint256 i = 0; i < all.length; i++) {
            if (acl.hasRole(all[i].role, all[i].grantee)) continue;
            vm.prank(SAFE);
            acl.grantRole(all[i].role, all[i].grantee);
        }
    }

    /// @notice Really revoke `role` from the retired signer, as the Safe.
    /// @param authoriser The clone to revoke on.
    /// @param role The action role to revoke.
    function revokeFromSigner(address authoriser, bytes32 role) internal {
        vm.prank(SAFE);
        IAccessControl(authoriser).revokeRole(role, SIGNER);
    }

    /// @notice Assert the returned canonical pairs are exactly the retired
    /// signer's three rows, in map order. Role, grantee AND order all
    /// matter: order decides which pair drives the reversal walk in
    /// `run()`, and the grantee is what makes these the retired signer's
    /// rows rather than another grantee's. Invariant across every state,
    /// because what the signer still holds changes the BUNDLE, never the
    /// map.
    /// @param retired The pairs returned alongside the bundle.
    function assertCanonicalPairs(RoleGrant[] memory retired) internal pure {
        assertEq(retired.length, 3, "the canonical map carries the retired signer's three rows");
        bytes32[3] memory roles = [DEPOSIT, WITHDRAW, CERTIFY];
        for (uint256 i = 0; i < roles.length; i++) {
            assertEq(retired[i].role, roles[i], "canonical pair role");
            assertEq(retired[i].grantee, SIGNER, "canonical pair grantee");
        }
    }

    /// @notice Assert `txn` is the `revokeRole(role, SIGNER)` call on
    /// `authoriser` — a plain value-free CALL, the only shape the Safe Tx
    /// Builder artifact can carry.
    /// @param txn The authored transaction.
    /// @param authoriser The expected destination.
    /// @param role The expected role in the encoded call.
    function assertRevokesRole(SafeTx memory txn, address authoriser, bytes32 role) internal pure {
        assertEq(txn.to, authoriser, "revoke tx must target the authoriser");
        assertEq(txn.value, 0, "revoke tx must carry no value");
        assertEq(uint256(txn.operation), 0, "revoke tx must be a CALL");
        assertEq(txn.data, abi.encodeCall(IAccessControl.revokeRole, (role, SIGNER)), "revoke tx calldata");
    }

    /// @notice Everything still held: all three canonical pairs are
    /// authored, in canonical map order.
    function testAuthorsEveryPairWhenEveryPairIsHeld() external {
        address authoriser = deployFullyGrantedAuthoriser();
        RevokeFireblocksServiceSignerHarness harness = new RevokeFireblocksServiceSignerHarness();

        (RoleGrant[] memory retired, SafeTx[] memory txs) = harness.callAuthorBundle(authoriser, SAFE);

        assertCanonicalPairs(retired);
        assertEq(txs.length, 3, "every pair is still held, so every pair is authored");
        assertRevokesRole(txs[0], authoriser, DEPOSIT);
        assertRevokesRole(txs[1], authoriser, WITHDRAW);
        assertRevokesRole(txs[2], authoriser, CERTIFY);
    }

    /// @notice Partial execution recovers by re-dispatch: with CERTIFY
    /// already revoked, only DEPOSIT and WITHDRAW are authored.
    function testAuthorsOnlyTheHeldPairsWhenCertifyIsRevoked() external {
        address authoriser = deployFullyGrantedAuthoriser();
        revokeFromSigner(authoriser, CERTIFY);
        RevokeFireblocksServiceSignerHarness harness = new RevokeFireblocksServiceSignerHarness();

        (RoleGrant[] memory retired, SafeTx[] memory txs) = harness.callAuthorBundle(authoriser, SAFE);

        assertCanonicalPairs(retired);
        assertEq(txs.length, 2, "the revoked pair is not re-authored");
        assertRevokesRole(txs[0], authoriser, DEPOSIT);
        assertRevokesRole(txs[1], authoriser, WITHDRAW);
    }

    /// @notice The self-scoping tracks WHICH pair is held, not merely how
    /// many: with the FIRST canonical pair already revoked the remaining
    /// two are authored, so the bundle cannot be a prefix of the map.
    function testAuthorsOnlyTheHeldPairsWhenDepositIsRevoked() external {
        address authoriser = deployFullyGrantedAuthoriser();
        revokeFromSigner(authoriser, DEPOSIT);
        RevokeFireblocksServiceSignerHarness harness = new RevokeFireblocksServiceSignerHarness();

        (RoleGrant[] memory retired, SafeTx[] memory txs) = harness.callAuthorBundle(authoriser, SAFE);

        assertCanonicalPairs(retired);
        assertEq(txs.length, 2, "the revoked pair is not re-authored");
        assertRevokesRole(txs[0], authoriser, WITHDRAW);
        assertRevokesRole(txs[1], authoriser, CERTIFY);
    }

    /// @notice A fully revoked authoriser refuses to author an empty
    /// bundle — the post-execution state, reached here by really revoking
    /// all three pairs.
    function testRevertsWhenEveryPairIsAlreadyRevoked() external {
        address authoriser = deployFullyGrantedAuthoriser();
        revokeFromSigner(authoriser, DEPOSIT);
        revokeFromSigner(authoriser, WITHDRAW);
        revokeFromSigner(authoriser, CERTIFY);
        RevokeFireblocksServiceSignerHarness harness = new RevokeFireblocksServiceSignerHarness();

        vm.expectRevert(FireblocksSignerAlreadyRevoked.selector);
        harness.callAuthorBundle(authoriser, SAFE);
    }

    /// @notice The revoke is never authored on an authoriser whose
    /// configuration has drifted: a missing NON-retired row aborts the
    /// authoring before any pair is selected. The row removed here is one
    /// of the REPLACEMENT signer's — this is the rotation gate: an
    /// under-provisioned replacement blocks the revoke, so the service can
    /// never be left without an active signer.
    function testRevertsWhenTheReplacementSignerIsUnderProvisioned() external {
        address authoriser = deployFullyGrantedAuthoriser();
        vm.prank(SAFE);
        IAccessControl(authoriser).revokeRole(DEPOSIT, LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
        RevokeFireblocksServiceSignerHarness harness = new RevokeFireblocksServiceSignerHarness();

        vm.expectRevert(bytes("RevokeFireblocksServiceSigner: authoriser grant map has drifted"));
        harness.callAuthorBundle(authoriser, SAFE);
    }

    /// @notice The drift guard is not specific to the replacement signer:
    /// a missing Safe-grantee row aborts the authoring identically.
    function testRevertsWhenTheGrantMapHasDrifted() external {
        address authoriser = deployFullyGrantedAuthoriser();
        vm.prank(SAFE);
        IAccessControl(authoriser).revokeRole(CERTIFY, SAFE);
        RevokeFireblocksServiceSignerHarness harness = new RevokeFireblocksServiceSignerHarness();

        vm.expectRevert(bytes("RevokeFireblocksServiceSigner: authoriser grant map has drifted"));
        harness.callAuthorBundle(authoriser, SAFE);
    }
}
