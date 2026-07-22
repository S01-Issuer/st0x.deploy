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

/// @notice Every production receipt vault already reports the V4 authoriser
/// clone — there is nothing left to swap. The script is done for this chain;
/// dispatching it again authors an empty bundle, which is never meaningful.
error NoVaultsLeftToSwap();

/// @notice A production receipt vault reports an authoriser that is neither
/// the V3 authoriser (the only acceptable pre-swap state) nor the V4 clone
/// (already swapped). An unknown authoriser on a production vault is exactly
/// the drift this script must never paper over with a blind `setAuthorizer`.
/// @param vault The receipt vault inspected.
/// @param actual The unexpected address returned by `authorizer()`.
error UnexpectedVaultAuthoriser(address vault, address actual);

/// @notice The pinned V4 authoriser clone has no runtime code.
/// @param clone The clone address that has no code.
error SwapCloneNotDeployed(address clone);

/// @notice The V4 authoriser clone's runtime codehash does not match the
/// pinned `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH`.
/// @param clone The clone address inspected.
/// @param expected The pinned clone codehash.
/// @param actual The codehash observed on-chain.
error SwapCloneCodehashMismatch(address clone, bytes32 expected, bytes32 actual);

/// @notice The V4 authoriser clone is missing one of the pinned role grants.
/// A vault must never be pointed at a clone whose grant map has drifted.
/// @param clone The clone address inspected.
/// @param role The missing role.
/// @param grantee The grantee that should hold the role.
error SwapCloneExpectedGrantMissing(address clone, bytes32 role, address grantee);

/// @title SwapRemainingVaultAuthorisers
/// @notice **PENDING.** Authors the Safe bundle that swaps every production
/// receipt vault still gated by the V3 authoriser onto the V4 authoriser
/// clone (`LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE`). Dispatch via
/// `Actions → run-script` with
/// `script = 20260722-swap-remaining-vault-authorisers` and `sig = run()`.
/// Flips to `**EXECUTED YYYY-MM-DD.**` in the post-execution pin PR.
///
/// The original V4 swap bundle (`20260623-upgrade-receipt-vaults-to-v4`,
/// executed 2026-07) covered every vault in the table at the time it was
/// signed. Tokens deployed AFTER that batch (MU / AMD / AVGO / AMAT / LRCX /
/// TTWO as of this script's authoring) came up wired to the V3 authoriser and
/// red-line the strict uniform-authoriser invariants until swapped. This
/// script is the follow-up batch — and deliberately SELF-SCOPING: rather than
/// hardcoding those six, it reads every production vault's live
/// `authorizer()` and targets exactly the ones still on V3. If another vault
/// lands un-swapped before this executes, re-dispatching regenerates a bundle
/// that covers it too; any vault on an UNKNOWN authoriser aborts the whole
/// authoring rather than being papered over.
///
/// This is a Safe-routed operation (`setAuthorizer` is `onlyOwner` and every
/// production vault is Safe-owned), so the script emits a Safe Tx Builder
/// JSON artifact for signer review + execution via the Safe UI. It never
/// broadcasts.
///
/// @dev Flow:
/// 1. **Pre-flight** —
///    - `assertAll(safe)` (the Safe is in its current expected state),
///    - the V4 clone is deployed with the pinned EIP-1167 codehash and
///      carries the full pinned grant map (the 11 `expectedGrants()` pairs
///      plus all seven auto-granted `_ADMIN` roles on the Safe),
///    - every production vault reports V3 (target) or the V4 clone (skip);
///      anything else reverts `UnexpectedVaultAuthoriser`.
/// 2. **Build** — one `setAuthorizer(V4 clone)` call per still-V3 vault.
///    Compute the canonical `SafeTxHash` against the live nonce for the
///    first tx for signer cross-check.
/// 3. **Simulate** — prank-route each bundle item as the Safe.
/// 4. **Post-state** — EVERY production vault (not just the targets) reports
///    the V4 clone (`assertUniformAuthoriser`, strict); Safe identity +
///    threshold unchanged.
/// 5. **Artifact** — emit the Tx Builder JSON to
///    `out/20260722-authoriser-swap.json`, frame it in the console log,
///    print the first tx's `SafeTxHash` + the target list.
/// 6. **n+1 re-issue** — prove the Safe can execute a further
///    `setAuthorizer` on a representative target under the live threshold.
///    NOTE the swap is ONE-WAY: the V4 vault implementation validates the
///    incoming authoriser and rejects one without a corporate-action role
///    admin (`AuthorizerMissingCorporateActionAdmin`), so rolling back to
///    the V3 authoriser is structurally impossible. The recovery path is
///    forward-only — the Safe (which stays owner, asserted in post-state)
///    can re-point vaults at any V4-compatible authoriser; the n+1 walk
///    proves that class of operation clears the threshold gate.
contract SwapRemainingVaultAuthorisers is Script {
    /// @notice The V4 authoriser clone every remaining vault is rewired onto.
    address internal constant V4_AUTHORISER_CLONE = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;

    /// @notice The V3 authoriser — the only acceptable pre-swap state for a
    /// target vault. NOT a rollback target: the V4 vault impl rejects it
    /// (`AuthorizerMissingCorporateActionAdmin`), so the swap is one-way.
    address internal constant V3_AUTHORISER = LibAuthoriserInvariants.STOX_PROD_AUTHORISER;

    /// @notice Human-readable name embedded in the emitted Tx Builder JSON's
    /// `meta.name`. Visible to signers in the Safe Tx Builder UI.
    string internal constant BUNDLE_NAME = "ST0x authoriser swap: remaining vaults onto the V4 clone";

    /// @notice Output path (relative to the project root) for the Tx Builder
    /// JSON artifact.
    string internal constant ARTIFACT_PATH = "out/20260722-authoriser-swap.json";

    /// @notice Author the follow-up authoriser swap: pre-flight invariants,
    /// select the still-V3 vaults, simulate every `setAuthorizer`, assert the
    /// strict uniform post-state, emit the Tx Builder JSON, log the
    /// SafeTxHash, and prove the forward-only n+1 re-issue clears the live
    /// threshold. Does not broadcast — execution happens via the Safe UI
    /// using the emitted artifact.
    function run() external {
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);

        // --- Pre-flight ---------------------------------------------------

        LibSafeInvariants.assertAll(safe);
        _preflightClone();
        address[] memory targets = _selectTargets();

        // --- Build the bundle ----------------------------------------------

        SafeTx[] memory txs = _buildBundle(targets);

        // Capture the nonce before any simulation. `simulateExternalCall`
        // does not advance the nonce, so the hash binds to the current Safe
        // state.
        uint256 nonce = safe.nonce();
        bytes32 firstSafeTxHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txs[0], nonce);

        // --- Simulate -----------------------------------------------------

        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(safe, txs[i].to, txs[i].data);
        }

        // --- Post-state ---------------------------------------------------

        // STRICT uniformity across the WHOLE table — the point of this batch
        // is that after it executes, no production vault is on anything but
        // the V4 clone. Safe identity + threshold unchanged.
        LibTokenInvariants.assertUniformAuthoriser(V4_AUTHORISER_CLONE);
        // Uniform Safe ownership is what keeps the (forward-only) recovery
        // path open after the swap, so it is asserted as part of the
        // post-state rather than assumed.
        LibTokenInvariants.assertUniformOwnership(address(safe));
        LibSafeInvariants.assertImmutableInvariants(safe);
        LibSafeInvariants.assertThreshold(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        // --- Artifact -----------------------------------------------------

        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, BUNDLE_NAME, txs);
        vm.writeFile(ARTIFACT_PATH, json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("First-tx SafeTxHash:", vm.toString(firstSafeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Bundle item count:", txs.length);
        for (uint256 i = 0; i < targets.length; i++) {
            console2.log("Target vault:", targets[i]);
        }

        // --- n+1 re-issue ---------------------------------------------------

        // The swap is ONE-WAY: the V4 vault impl validates the incoming
        // authoriser and reverts `AuthorizerMissingCorporateActionAdmin` for
        // the V3 authoriser, so a literal rollback is impossible by design.
        // The available recovery class is forward-only — the Safe re-points
        // the vault at a V4-compatible authoriser. Prove that class clears
        // the live threshold gate by re-issuing `setAuthorizer(V4 clone)` on
        // a representative target through the n+1 walk (which also proves an
        // undersigned attempt is rejected).
        bytes memory reissueData =
            abi.encodeCall(OffchainAssetReceiptVaultLike.setAuthorizer, (IAuthorizeV1(V4_AUTHORISER_CLONE)));
        LibSafeOps.simulateNPlus1(safe, targets[0], reissueData, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
        require(
            address(IAuthorizableV1(targets[0]).authorizer()) == V4_AUTHORISER_CLONE,
            "SwapRemainingVaultAuthorisers: n+1 re-issue did not leave the vault on the V4 clone"
        );
        console2.log(
            "n+1 re-issue check passed: the Safe can re-point a vault under the live threshold"
            " (rollback to V3 is structurally impossible - forward-only recovery)"
        );
    }

    /// @notice Pre-flight: the V4 authoriser clone is deployed at its pin
    /// with the pinned EIP-1167 codehash and carries the full grant map —
    /// the 11 `expectedGrants()` pairs plus all seven auto-granted `_ADMIN`
    /// roles on the Safe (including the two V4-only corporate-action admins
    /// the lib map doesn't carry). A vault must never be pointed at a clone
    /// whose configuration has drifted.
    function _preflightClone() internal view {
        if (V4_AUTHORISER_CLONE.code.length == 0) {
            revert SwapCloneNotDeployed(V4_AUTHORISER_CLONE);
        }
        bytes32 cloneCodehash = V4_AUTHORISER_CLONE.codehash;
        if (cloneCodehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH) {
            revert SwapCloneCodehashMismatch(
                V4_AUTHORISER_CLONE, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH, cloneCodehash
            );
        }
        IAccessControl cloneAcl = IAccessControl(V4_AUTHORISER_CLONE);
        RoleGrant[] memory expected = LibAuthoriserInvariants.expectedGrants();
        for (uint256 i = 0; i < expected.length; i++) {
            if (!cloneAcl.hasRole(expected[i].role, expected[i].grantee)) {
                revert SwapCloneExpectedGrantMissing(V4_AUTHORISER_CLONE, expected[i].role, expected[i].grantee);
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
            if (!cloneAcl.hasRole(adminRoles[i], ownerSafe)) {
                revert SwapCloneExpectedGrantMissing(V4_AUTHORISER_CLONE, adminRoles[i], ownerSafe);
            }
        }
    }

    /// @notice Select the swap targets from live chain state: every
    /// production receipt vault still reporting the V3 authoriser. A vault
    /// already on the V4 clone is skipped; a vault on anything else aborts
    /// the authoring (`UnexpectedVaultAuthoriser`). Reverts
    /// `NoVaultsLeftToSwap` when the whole table is already on the clone —
    /// the script has nothing to author and is done for this chain.
    /// @return targets The still-V3 vaults, in table order.
    function _selectTargets() internal view returns (address[] memory targets) {
        address[] memory vaults = LibTokenInvariants.productionReceiptVaults();
        address[] memory candidates = new address[](vaults.length);
        uint256 count = 0;
        for (uint256 i = 0; i < vaults.length; i++) {
            address actual = address(IAuthorizableV1(vaults[i]).authorizer());
            if (actual == V4_AUTHORISER_CLONE) {
                continue;
            }
            if (actual != V3_AUTHORISER) {
                revert UnexpectedVaultAuthoriser(vaults[i], actual);
            }
            candidates[count] = vaults[i];
            count++;
        }
        if (count == 0) {
            revert NoVaultsLeftToSwap();
        }
        targets = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            targets[i] = candidates[i];
        }
    }

    /// @notice Build the bundle: one `setAuthorizer(V4 clone)` per target.
    /// @param targets The still-V3 vaults the swap covers.
    /// @return txs The bundle transactions in execution order.
    function _buildBundle(address[] memory targets) internal pure returns (SafeTx[] memory txs) {
        bytes memory setAuthoriserData =
            abi.encodeCall(OffchainAssetReceiptVaultLike.setAuthorizer, (IAuthorizeV1(V4_AUTHORISER_CLONE)));
        txs = new SafeTx[](targets.length);
        for (uint256 i = 0; i < targets.length; i++) {
            txs[i] = SafeTx({to: targets[i], value: 0, data: setAuthoriserData, operation: 0});
        }
    }
}

/// @dev Local mirror of the receipt-vault `setAuthorizer(IAuthorizeV1)`
/// selector. Avoids dragging the full `OffchainAssetReceiptVault` storage
/// inheritance into this script just to encode one selector.
interface OffchainAssetReceiptVaultLike {
    function setAuthorizer(IAuthorizeV1 newAuthorizer) external;
}
