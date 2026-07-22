// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";

import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IAuthorizableV1} from "rain-vats-0.1.6/src/interface/IAuthorizableV1.sol";
import {IAuthorizeV1} from "rain-vats-0.1.6/src/interface/IAuthorizeV1.sol";
import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTokenInvariants} from "../src/lib/LibTokenInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";

/// @notice The RKLB receipt vault already reports the V4 authoriser — the
/// swap has executed and this script has nothing to author.
/// @param actual The authoriser the vault reports (the V4 authoriser).
error RklbAlreadySwapped(address actual);

/// @notice The RKLB receipt vault reports an authoriser that is neither the
/// V3 authoriser (the only acceptable pre-swap state) nor the V4 authoriser
/// (already swapped). Unknown drift must abort the authoring, never be
/// papered over with a blind `setAuthorizer`.
/// @param actual The unexpected address returned by `authorizer()`.
error UnexpectedRklbAuthoriser(address actual);

/// @notice The pinned V4 authoriser has no runtime code.
/// @param authoriser The authoriser address that has no code.
error RklbSwapAuthoriserNotDeployed(address authoriser);

/// @notice The V4 authoriser's runtime codehash does not match the pin.
/// @param authoriser The authoriser address inspected.
/// @param expected The pinned codehash.
/// @param actual The codehash observed on-chain.
error RklbSwapAuthoriserCodehashMismatch(address authoriser, bytes32 expected, bytes32 actual);

/// @notice The V4 authoriser is missing one of the pinned role grants.
/// @param authoriser The authoriser address inspected.
/// @param role The missing role.
/// @param grantee The grantee that should hold the role.
error RklbSwapAuthoriserGrantMissing(address authoriser, bytes32 role, address grantee);

/// @title SwapRklbAuthoriser
/// @notice **PENDING.** Authors the SINGLE-tx Safe bundle that swaps the
/// RKLB receipt vault onto the V4 authoriser
/// (`LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE`). Dispatch via
/// `Actions → run-script` with `script = 20260722-swap-rklb-authoriser` and
/// `sig = run()`. Flips to `**EXECUTED YYYY-MM-DD.**` in the post-execution
/// pin PR.
///
/// Deliberately scoped to RKLB ALONE: the six other still-V3 vaults are
/// covered by a bundle authored from
/// `20260722-swap-remaining-vault-authorisers` that is already partially
/// signed (2-of-3 at the time of this script's authoring). Regenerating a
/// combined 7-tx bundle would change the SafeTxHash and void those
/// signatures, so RKLB — added to the canonical table after that bundle was
/// authored — gets its own single tx instead. The two bundles target
/// disjoint vaults and are order-independent. Once both execute, the
/// self-scoping general script reverts `NoVaultsLeftToSwap` and the strict
/// uniform-authoriser invariants go green across the whole table.
///
/// This is a Safe-routed operation (`setAuthorizer` is `onlyOwner`; the
/// vault is Safe-owned), so the script emits a Safe Tx Builder JSON artifact
/// for signer review + execution via the Safe UI. It never broadcasts.
///
/// @dev Flow mirrors the general swap authoring, narrowed to one vault:
/// pre-flight (Safe state, V4 authoriser codehash + full grant map, RKLB
/// strictly on V3), build the single `setAuthorizer` tx, compute its
/// `SafeTxHash` against the live nonce, simulate as the Safe, assert the
/// post-state (RKLB on the V4 authoriser; Safe identity + threshold
/// unchanged — deliberately NOT whole-table uniformity, since the six-vault
/// bundle executes independently), emit the artifact to
/// `out/20260722-rklb-authoriser-swap.json`, and prove the forward-only n+1
/// re-issue clears the live threshold (rollback to V3 is structurally
/// impossible: the V4 vault impl rejects an authoriser without a
/// corporate-action role admin).
contract SwapRklbAuthoriser is Script {
    /// @notice The RKLB receipt vault the single tx targets.
    address internal constant RKLB_RECEIPT_VAULT = LibTokenInvariants.RKLB_RECEIPT_VAULT;

    /// @notice The V4 authoriser the vault is rewired onto.
    address internal constant V4_AUTHORISER = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;

    /// @notice The V3 authoriser — the only acceptable pre-swap state.
    address internal constant V3_AUTHORISER = LibAuthoriserInvariants.STOX_PROD_AUTHORISER;

    /// @notice Human-readable name embedded in the emitted Tx Builder JSON's
    /// `meta.name`. Visible to signers in the Safe Tx Builder UI.
    string internal constant BUNDLE_NAME = "ST0x authoriser swap: RKLB onto the V4 authoriser";

    /// @notice Output path (relative to the project root) for the Tx Builder
    /// JSON artifact.
    string internal constant ARTIFACT_PATH = "out/20260722-rklb-authoriser-swap.json";

    /// @notice Author the RKLB authoriser swap: pre-flight invariants,
    /// simulate the single `setAuthorizer`, assert the post-state, emit the
    /// Tx Builder JSON, log the SafeTxHash, and prove the forward-only n+1
    /// re-issue clears the live threshold. Does not broadcast — execution
    /// happens via the Safe UI using the emitted artifact.
    function run() external {
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);

        // --- Pre-flight ---------------------------------------------------

        LibSafeInvariants.assertAll(safe);
        _preflightAuthoriser();

        // RKLB must be STRICTLY on the V3 authoriser: already-swapped means
        // done (revert, nothing to author); anything else is unknown drift.
        address actual = address(IAuthorizableV1(RKLB_RECEIPT_VAULT).authorizer());
        if (actual == V4_AUTHORISER) {
            revert RklbAlreadySwapped(actual);
        }
        if (actual != V3_AUTHORISER) {
            revert UnexpectedRklbAuthoriser(actual);
        }

        // --- Build the single tx ------------------------------------------

        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({
            to: RKLB_RECEIPT_VAULT,
            value: 0,
            data: abi.encodeCall(OffchainAssetReceiptVaultLike.setAuthorizer, (IAuthorizeV1(V4_AUTHORISER))),
            operation: 0
        });

        // Capture the nonce before simulation so the hash binds to the
        // current Safe state.
        uint256 nonce = safe.nonce();
        bytes32 safeTxHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txs[0], nonce);

        // --- Simulate -----------------------------------------------------

        LibSafeOps.simulateExternalCall(safe, txs[0].to, txs[0].data);

        // --- Post-state ---------------------------------------------------

        // RKLB now reports the V4 authoriser. Deliberately NOT whole-table
        // uniformity: the six-vault bundle executes independently and its
        // state must not gate this authoring. Safe identity + threshold
        // unchanged.
        address post = address(IAuthorizableV1(RKLB_RECEIPT_VAULT).authorizer());
        require(post == V4_AUTHORISER, "SwapRklbAuthoriser: simulated swap did not land on the V4 authoriser");
        LibSafeInvariants.assertImmutableInvariants(safe);
        LibSafeInvariants.assertThreshold(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        // --- Artifact -----------------------------------------------------

        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, BUNDLE_NAME, txs);
        vm.writeFile(ARTIFACT_PATH, json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("SafeTxHash:", vm.toString(safeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Target vault (RKLB):", RKLB_RECEIPT_VAULT);

        // --- n+1 re-issue ---------------------------------------------------

        // Forward-only recovery proof; see the general swap script for why a
        // V3 rollback is structurally impossible on V4 vault impls.
        bytes memory reissueData =
            abi.encodeCall(OffchainAssetReceiptVaultLike.setAuthorizer, (IAuthorizeV1(V4_AUTHORISER)));
        LibSafeOps.simulateNPlus1(
            safe, RKLB_RECEIPT_VAULT, reissueData, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
        );
        require(
            address(IAuthorizableV1(RKLB_RECEIPT_VAULT).authorizer()) == V4_AUTHORISER,
            "SwapRklbAuthoriser: n+1 re-issue did not leave the vault on the V4 authoriser"
        );
        console2.log("n+1 re-issue check passed: the Safe can re-point the vault under the live threshold");
    }

    /// @notice Pre-flight: the V4 authoriser is deployed at its pin with the
    /// pinned EIP-1167 codehash and carries the full grant map — the 11
    /// `expectedGrants()` pairs plus all seven auto-granted `_ADMIN` roles
    /// on the Safe. The vault must never be pointed at an authoriser whose
    /// configuration has drifted.
    function _preflightAuthoriser() internal view {
        if (V4_AUTHORISER.code.length == 0) {
            revert RklbSwapAuthoriserNotDeployed(V4_AUTHORISER);
        }
        bytes32 codehash = V4_AUTHORISER.codehash;
        if (codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH) {
            revert RklbSwapAuthoriserCodehashMismatch(
                V4_AUTHORISER, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH, codehash
            );
        }
        IAccessControl acl = IAccessControl(V4_AUTHORISER);
        RoleGrant[] memory expected = LibAuthoriserInvariants.expectedGrants();
        for (uint256 i = 0; i < expected.length; i++) {
            if (!acl.hasRole(expected[i].role, expected[i].grantee)) {
                revert RklbSwapAuthoriserGrantMissing(V4_AUTHORISER, expected[i].role, expected[i].grantee);
            }
        }
        bytes32[7] memory adminRoles = [
            keccak256("CERTIFY_ADMIN"),
            keccak256("CONFISCATE_RECEIPT_ADMIN"),
            keccak256("CONFISCATE_SHARES_ADMIN"),
            keccak256("DEPOSIT_ADMIN"),
            keccak256("WITHDRAW_ADMIN"),
            keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN"),
            keccak256("CANCEL_CORPORATE_ACTION_ADMIN")
        ];
        address ownerSafe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        for (uint256 i = 0; i < adminRoles.length; i++) {
            if (!acl.hasRole(adminRoles[i], ownerSafe)) {
                revert RklbSwapAuthoriserGrantMissing(V4_AUTHORISER, adminRoles[i], ownerSafe);
            }
        }
    }
}

/// @dev Local mirror of the receipt-vault `setAuthorizer(IAuthorizeV1)`
/// selector; see the 20260706 script for the full rationale.
interface OffchainAssetReceiptVaultLike {
    function setAuthorizer(IAuthorizeV1 newAuthorizer) external;
}
