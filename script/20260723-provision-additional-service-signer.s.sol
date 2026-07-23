// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";

import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";

/// @notice The additional service signer already holds every canonical
/// additional grant on this chain — the provisioning has executed and there
/// is nothing left to author.
error AdditionalSignerAlreadyProvisioned();

/// @notice The active chain has no usable V4 authoriser (unsupported chain,
/// unhydrated pin, no code, or codehash drift).
/// @param authoriser The authoriser address inspected (`address(0)` when
/// the chain's pin is unhydrated).
error AuthoriserNotReadyForProvisioning(address authoriser);

/// @notice No V4 authoriser pin exists for the active chain at all.
/// @param chainId The unsupported chain id.
error UnsupportedChainForProvisioning(uint256 chainId);

/// @notice The Safe does not hold the `_ADMIN` role that admins one of the
/// provisioned roles — the grant would revert inside the Safe tx.
/// @param adminRole The missing admin role.
error SafeMissingRoleAdmin(bytes32 adminRole);

/// @title ProvisionAdditionalServiceSigner
/// @notice **PENDING.** Authors the Safe bundle that provisions the
/// ADDITIONAL service signer
/// (`LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C`) on the ACTIVE chain's
/// V4 authoriser with the canonical post-ceremony grants
/// (`additionalServiceGrants()`: `DEPOSIT` / `WITHDRAW` / `CERTIFY` — the
/// same three action roles the original service signer holds; both signers
/// are active side by side, nothing is revoked). Dispatch via
/// `Actions → run-script` with
/// `script = 20260723-provision-additional-service-signer`, `sig = run()`,
/// and the target `network`; one dispatch + Safe signing per chain carrying
/// a live authoriser (Base and Ethereum today; HyperEVM after its
/// authoriser bootstraps). Flips to `**EXECUTED YYYY-MM-DD (<chain>).**`
/// per chain in the post-execution pin PR.
///
/// The canonical pairs are the `GRANTEE_SERVICE_3D0C` rows of
/// `LibAuthoriserInvariants.expectedGrants()` — the single current-state
/// map every live invariant asserts (the cross-chain parity authoriser
/// leg, the multichain production-state bundle, the per-chain prod pins) —
/// so each chain is RED on this signer's rows until this bundle executes
/// there, and guarded against drift thereafter.
///
/// SELF-SCOPING: only the pairs the signer does not yet hold are authored
/// (partial execution recovers by re-dispatch); a fully provisioned chain
/// refuses to author an empty bundle.
///
/// @dev Flow: pre-flight (Safe state via the shared chain-aware entry
/// point; authoriser pinned + deployed + pinned codehash; the ceremony
/// grant map intact; Safe holds the `_ADMIN` role for every provisioned
/// role) -> build one `grantRole` tx per missing pair -> SafeTxHash against
/// the live nonce -> simulate as the Safe -> post-state (every additional
/// pair holds; ceremony map untouched; Safe identity + threshold
/// unchanged) -> artifact to
/// `out/20260723-additional-service-signer.json` -> n+1 walk proving the
/// provisioning is REVERSIBLE (revoke sits under the same `_ADMIN` the
/// Safe holds): revoke the first role under the live threshold, then
/// re-grant so the simulated fork ends provisioned.
contract ProvisionAdditionalServiceSigner is Script {
    /// @notice The additional service signer being provisioned — the
    /// canonical pin from the invariant lib.
    address internal constant ADDITIONAL_SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

    /// @notice Human-readable name embedded in the emitted Tx Builder JSON's
    /// `meta.name`. Visible to signers in the Safe Tx Builder UI.
    string internal constant BUNDLE_NAME = "ST0x provision: additional service signer on the V4 authoriser";

    /// @notice Output path (relative to the project root) for the Tx Builder
    /// JSON artifact.
    string internal constant ARTIFACT_PATH = "out/20260723-additional-service-signer.json";

    /// @notice The `_ADMIN` role that admins `role` under the authoriser's
    /// hierarchy (`<ROLE>` is admined by `<ROLE>_ADMIN`; verified live).
    /// @param role The action role.
    /// @return adminRole The role's admin role.
    function roleAdminOf(bytes32 role) internal pure returns (bytes32 adminRole) {
        if (role == keccak256("DEPOSIT")) return keccak256("DEPOSIT_ADMIN");
        if (role == keccak256("WITHDRAW")) return keccak256("WITHDRAW_ADMIN");
        if (role == keccak256("CERTIFY")) return keccak256("CERTIFY_ADMIN");
        revert("ProvisionAdditionalServiceSigner: no admin mapping for role");
    }

    /// @notice The active chain's hydrated V4 authoriser, asserted deployed
    /// with the shared EIP-1167 codehash.
    /// @return authoriser The validated authoriser address.
    function activeChainAuthoriser() internal view returns (address authoriser) {
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        } else if (block.chainid == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
        } else {
            revert UnsupportedChainForProvisioning(block.chainid);
        }
        if (
            authoriser == address(0) || authoriser.code.length == 0
                || authoriser.codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
        ) {
            revert AuthoriserNotReadyForProvisioning(authoriser);
        }
    }

    /// @notice Author the provisioning bundle for the active chain: see the
    /// contract-level flow. Does not broadcast — execution happens via the
    /// Safe UI using the emitted artifact.
    function run() external {
        // --- Pre-flight ---------------------------------------------------

        address safeAddr = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        IGnosisSafe safe = IGnosisSafe(safeAddr);

        address authoriser = activeChainAuthoriser();
        IAccessControl acl = IAccessControl(authoriser);

        // Split the canonical map: the additional signer's rows are the
        // work items; every OTHER row must already hold — the signer must
        // never be provisioned on an authoriser whose configuration has
        // drifted.
        RoleGrant[] memory all = LibAuthoriserInvariants.expectedGrants(safeAddr);
        uint256 pairCount = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].grantee == ADDITIONAL_SIGNER) {
                pairCount++;
                continue;
            }
            require(
                acl.hasRole(all[i].role, all[i].grantee),
                "ProvisionAdditionalServiceSigner: authoriser grant map has drifted"
            );
        }
        RoleGrant[] memory additional = new RoleGrant[](pairCount);
        uint256 p = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].grantee == ADDITIONAL_SIGNER) {
                additional[p] = all[i];
                p++;
            }
        }

        // The Safe holds the `_ADMIN` role for every provisioned role.
        for (uint256 i = 0; i < additional.length; i++) {
            bytes32 adminRole = roleAdminOf(additional[i].role);
            if (!acl.hasRole(adminRole, safeAddr)) {
                revert SafeMissingRoleAdmin(adminRole);
            }
        }

        // Self-scope to the pairs not yet held.
        bool[] memory missing = new bool[](additional.length);
        uint256 count = 0;
        for (uint256 i = 0; i < additional.length; i++) {
            if (!acl.hasRole(additional[i].role, additional[i].grantee)) {
                missing[i] = true;
                count++;
            }
        }
        if (count == 0) {
            revert AdditionalSignerAlreadyProvisioned();
        }

        // --- Build the bundle ----------------------------------------------

        SafeTx[] memory txs = new SafeTx[](count);
        uint256 t = 0;
        for (uint256 i = 0; i < additional.length; i++) {
            if (!missing[i]) continue;
            txs[t] = SafeTx({
                to: authoriser,
                value: 0,
                data: abi.encodeCall(IAccessControl.grantRole, (additional[i].role, additional[i].grantee)),
                operation: 0
            });
            t++;
        }

        uint256 nonce = safe.nonce();
        bytes32 firstSafeTxHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txs[0], nonce);

        // --- Simulate -----------------------------------------------------

        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(safe, txs[i].to, txs[i].data);
        }

        // --- Post-state ---------------------------------------------------

        // The full current-state map holds — the exact bundle
        // `assertExpectedGrants` enforces in CI — and the Safe identity +
        // threshold are unchanged.
        LibAuthoriserInvariants.assertExpectedGrants(authoriser, safeAddr);
        LibSafeInvariants.assertImmutableInvariants(safe);
        LibSafeInvariants.assertThreshold(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        // --- Artifact -----------------------------------------------------

        string memory json = LibSafeOps.emitTxBuilderJson(safeAddr, block.chainid, BUNDLE_NAME, txs);
        vm.writeFile(ARTIFACT_PATH, json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("First-tx SafeTxHash:", vm.toString(firstSafeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Bundle item count:", txs.length);
        console2.log("Chain:", block.chainid);
        console2.log("Authoriser:", authoriser);
        console2.log("Additional signer:", ADDITIONAL_SIGNER);

        // --- n+1 reversal proof --------------------------------------------

        // The provisioning is fully reversible (revoke sits under the same
        // `_ADMIN` the Safe holds). Prove the revoke clears the live
        // threshold on the first role, then re-grant so the fork ends
        // provisioned.
        LibSafeOps.simulateNPlus1(
            safe,
            authoriser,
            abi.encodeCall(IAccessControl.revokeRole, (additional[0].role, additional[0].grantee)),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
        );
        require(
            !acl.hasRole(additional[0].role, additional[0].grantee),
            "ProvisionAdditionalServiceSigner: n+1 revoke did not remove the role"
        );
        LibSafeOps.simulateExternalCall(
            safe, authoriser, abi.encodeCall(IAccessControl.grantRole, (additional[0].role, additional[0].grantee))
        );
        console2.log("n+1 reversal check passed: the Safe can revoke (and re-grant) under the live threshold");
    }
}
