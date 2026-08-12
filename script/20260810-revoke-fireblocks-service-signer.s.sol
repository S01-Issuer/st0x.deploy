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

/// @notice The retired Fireblocks service signer no longer holds any of its
/// canonical grants on this chain — the revocation has executed and there
/// is nothing left to author.
error FireblocksSignerAlreadyRevoked();

/// @notice The active chain has no usable V4 authoriser (unsupported chain,
/// unhydrated pin, no code, or codehash drift).
/// @param authoriser The authoriser address inspected (`address(0)` when
/// the chain's pin is unhydrated).
error AuthoriserNotReadyForRevocation(address authoriser);

/// @notice No V4 authoriser pin exists for the active chain at all.
/// @param chainId The unsupported chain id.
error UnsupportedChainForRevocation(uint256 chainId);

/// @notice The Safe does not hold the `_ADMIN` role that admins one of the
/// revoked roles — the revoke would revert inside the Safe tx.
/// @param adminRole The missing admin role.
error SafeMissingRoleAdmin(bytes32 adminRole);

/// @title RevokeFireblocksServiceSigner
/// @notice **PENDING.** Authors the Safe bundle that revokes the RETIRED
/// Fireblocks-custodied service signer
/// (`LibAuthoriserInvariants.GRANTEE_SERVICE_1C66`) from the ACTIVE chain's
/// V4 authoriser: one `revokeRole` per canonical grant the signer still
/// holds (`DEPOSIT` / `WITHDRAW` / `CERTIFY` — the map's `1C66` rows). The
/// signer's duties moved to the additional service signer
/// (`GRANTEE_SERVICE_3D0C`, provisioned by the `20260723` bundle on every
/// live chain), so this is the second half of the signer rotation: the
/// Fireblocks wallet loses its authoriser roles and the map converges on
/// the replacement signer. Dispatch via `Actions → run-script` with
/// `script = 20260810-revoke-fireblocks-service-signer`, `sig = run()`,
/// and the target `network`; one dispatch + Safe signing per chain
/// carrying a live authoriser — `base`, `ethereum` and `hyperevm`, all
/// three of which hold the signer's three canonical pairs today.
///
/// SAFETY — the drift guard doubles as a rotation gate: pre-flight
/// requires every NON-retired row of
/// `LibAuthoriserInvariants.expectedGrants()` to hold, which includes all
/// three of the replacement signer's rows. A chain where the replacement
/// signer is not fully provisioned therefore refuses to author the
/// revoke, so the service can never be left without an active signer.
///
/// The canonical map still carries the retired signer's rows — it pins
/// what production IS, and the signer holds its grants until the Safes
/// sign. Executing this bundle on a chain turns that chain's `1C66` rows
/// red (`ExpectedGrantMissing`) in every live invariant — the cross-chain
/// parity authoriser leg, the multichain production-state bundle, the
/// per-chain prod pins — forcing the post-execution pin PR that removes
/// the rows from the map and pins their ABSENCE as the new negative
/// invariant. The prod pin for this script
/// (`20260810-revoke-fireblocks-service-signer.prod.t.sol`) works the
/// same way in the opposite direction: it asserts `run()` authors a
/// full three-pair bundle on each chain, so execution flips it to
/// `FireblocksSignerAlreadyRevoked` and it retires in the same pin PR.
///
/// SELF-SCOPING: only the pairs the signer still holds are authored
/// (partial execution recovers by re-dispatch); a fully revoked chain
/// refuses to author an empty bundle.
///
/// @dev Flow: pre-flight (Safe state via the shared chain-aware entry
/// point; authoriser pinned + deployed + pinned codehash; every
/// non-retired row of the ceremony grant map intact; Safe holds the
/// `_ADMIN` role for every revoked role) -> build one `revokeRole` tx per
/// still-held pair -> SafeTxHash against the live nonce -> simulate as the
/// Safe -> post-state (the retired signer holds nothing; every other row
/// untouched; Safe identity + threshold unchanged) -> artifact to
/// `out/20260810-revoke-fireblocks-service-signer-<chainid>.json` -> n+1 walk
/// proving the revocation is REVERSIBLE (re-grant sits under the same
/// `_ADMIN` the Safe holds): re-grant the first role under the live
/// threshold, then revoke again so the simulated fork ends revoked.
contract RevokeFireblocksServiceSigner is Script {
    /// @notice The retired Fireblocks service signer being revoked — the
    /// canonical pin from the invariant lib.
    address internal constant RETIRED_SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_1C66;

    /// @notice Human-readable name embedded in the emitted Tx Builder JSON's
    /// `meta.name`. Visible to signers in the Safe Tx Builder UI.
    string internal constant BUNDLE_NAME = "ST0x revoke: retired Fireblocks service signer on the V4 authoriser";

    /// @notice Output path (relative to the project root) for the Tx Builder
    /// JSON artifact. Chain-suffixed — unlike the single-chain-at-a-time
    /// predecessors, this operation dispatches against three chains in one
    /// operational window, and a shared path would let one chain's bundle
    /// silently overwrite another's (in a signer's download folder as
    /// readily as in the test suite's shared `out/`).
    /// Virtual so a test that authors DIFFERENT bundle content on the same
    /// chain (the partial-re-dispatch fixture) can write to its own path:
    /// forge runs tests in parallel and same-chain tests otherwise share
    /// this file, which is benign only while every writer produces
    /// identical bytes.
    /// @return path The artifact path for the ACTIVE chain.
    function artifactPath() internal view virtual returns (string memory path) {
        path = string.concat("out/20260810-revoke-fireblocks-service-signer-", vm.toString(block.chainid), ".json");
    }

    /// @notice The `_ADMIN` role that admins `role` under the authoriser's
    /// hierarchy: `<ROLE>` is admined by `<ROLE>_ADMIN`.
    /// @dev Hardcoding the mapping is safe rather than lucky. The hierarchy
    /// is written by `_setRoleAdmin` inside the authoriser's `initialize`
    /// and nowhere else — OpenZeppelin's `_setRoleAdmin` is `internal` and
    /// `AccessControlUpgradeable` exposes no external setter — so a given
    /// implementation's mapping is fixed at initialisation and immutable
    /// thereafter. `activeChainAuthoriser()` asserts the clone's runtime
    /// codehash equals the pinned EIP-1167 runtime embedding the audited
    /// 0.1.1 implementation, which is therefore proof of WHICH mapping the
    /// clone carries. A live `getRoleAdmin` read would be re-deriving what
    /// the codehash pin already establishes.
    /// @param role The action role.
    /// @return adminRole The role's admin role.
    function roleAdminOf(bytes32 role) internal pure returns (bytes32 adminRole) {
        if (role == keccak256("DEPOSIT")) return keccak256("DEPOSIT_ADMIN");
        if (role == keccak256("WITHDRAW")) return keccak256("WITHDRAW_ADMIN");
        if (role == keccak256("CERTIFY")) return keccak256("CERTIFY_ADMIN");
        revert("RevokeFireblocksServiceSigner: no admin mapping for role");
    }

    /// @notice The active chain's hydrated V4 authoriser, asserted deployed
    /// with the shared EIP-1167 codehash.
    /// @return authoriser The validated authoriser address.
    function activeChainAuthoriser() internal view returns (address authoriser) {
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        } else if (block.chainid == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
        } else if (block.chainid == LibSafeInvariants.HYPEREVM_CHAIN_ID) {
            authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM;
        } else {
            revert UnsupportedChainForRevocation(block.chainid);
        }
        if (
            authoriser == address(0) || authoriser.code.length == 0
                || authoriser.codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
        ) {
            revert AuthoriserNotReadyForRevocation(authoriser);
        }
    }

    /// @notice Pre-flight the authoriser's grant map and self-scope the
    /// bundle: the retired signer's canonical pairs, plus one `revokeRole`
    /// transaction per pair the signer still holds.
    ///
    /// Reverts when the map has drifted (any non-retired row missing — which
    /// includes every replacement-signer row, so an under-provisioned chain
    /// can never author the revoke), when the Safe does not admin a revoked
    /// role, or when no pair holds any longer
    /// (`FireblocksSignerAlreadyRevoked` — nothing left to author).
    ///
    /// @dev Every chain-specific input arrives as an argument rather than
    /// being read from `block.chainid`, so the selection is exercisable
    /// against ANY authoriser carrying the canonical map — a locally
    /// cloned one in the unit suite as readily as a pinned production
    /// clone on a fork.
    /// @param authoriser The authoriser whose live role state is read.
    /// @param safeAddr The chain's token-owner Safe: fills the Safe
    /// grantee slots of the canonical map and holds every `_ADMIN` role.
    /// @return retired The retired signer's canonical pairs, in map order.
    /// @return txs One `revokeRole` tx per pair the signer still holds,
    /// in map order.
    function authorBundle(address authoriser, address safeAddr)
        internal
        view
        returns (RoleGrant[] memory retired, SafeTx[] memory txs)
    {
        IAccessControl acl = IAccessControl(authoriser);

        // Split the canonical map: the retired signer's rows are the work
        // items; every OTHER row must already hold — the revoke must never
        // be authored on an authoriser whose configuration has drifted,
        // and the replacement signer's rows being part of "every other
        // row" is the rotation gate described in the contract NatSpec.
        RoleGrant[] memory all = LibAuthoriserInvariants.expectedGrants(safeAddr);
        uint256 pairCount = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].grantee == RETIRED_SIGNER) {
                pairCount++;
                continue;
            }
            require(
                acl.hasRole(all[i].role, all[i].grantee),
                "RevokeFireblocksServiceSigner: authoriser grant map has drifted"
            );
        }
        retired = new RoleGrant[](pairCount);
        uint256 p = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].grantee == RETIRED_SIGNER) {
                retired[p] = all[i];
                p++;
            }
        }

        // The Safe holds the `_ADMIN` role for every revoked role.
        for (uint256 i = 0; i < retired.length; i++) {
            bytes32 adminRole = roleAdminOf(retired[i].role);
            if (!acl.hasRole(adminRole, safeAddr)) {
                revert SafeMissingRoleAdmin(adminRole);
            }
        }

        // Self-scope to the pairs still held.
        bool[] memory held = new bool[](retired.length);
        uint256 count = 0;
        for (uint256 i = 0; i < retired.length; i++) {
            if (acl.hasRole(retired[i].role, retired[i].grantee)) {
                held[i] = true;
                count++;
            }
        }
        if (count == 0) {
            revert FireblocksSignerAlreadyRevoked();
        }

        txs = new SafeTx[](count);
        uint256 t = 0;
        for (uint256 i = 0; i < retired.length; i++) {
            if (!held[i]) continue;
            txs[t] = SafeTx({
                to: authoriser,
                value: 0,
                data: abi.encodeCall(IAccessControl.revokeRole, (retired[i].role, retired[i].grantee)),
                operation: 0
            });
            t++;
        }
    }

    /// @notice Assert the post-revocation grant state on the active fork:
    /// the retired signer holds NONE of its canonical roles (and no
    /// `DEFAULT_ADMIN_ROLE`), while every other row of the canonical map
    /// still holds — the revoke touched exactly the retired signer's rows.
    /// @dev The map-wide `assertExpectedGrants` cannot be used here: the
    /// canonical map still carries the retired signer's rows (it pins what
    /// production IS until the bundle executes), so the post-state is
    /// asserted row-by-row with the retired rows negated. The pin PR that
    /// lands after execution moves this negation into the invariant lib.
    /// @param acl The authoriser's access-control surface.
    /// @param safeAddr The chain's token-owner Safe filling the map's Safe
    /// grantee slots.
    function assertPostRevocationState(IAccessControl acl, address safeAddr) internal view {
        RoleGrant[] memory all = LibAuthoriserInvariants.expectedGrants(safeAddr);
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].grantee == RETIRED_SIGNER) {
                require(
                    !acl.hasRole(all[i].role, all[i].grantee),
                    "RevokeFireblocksServiceSigner: retired signer still holds a canonical role"
                );
            } else {
                require(
                    acl.hasRole(all[i].role, all[i].grantee),
                    "RevokeFireblocksServiceSigner: revocation disturbed an unrelated grant"
                );
            }
        }
        require(
            !acl.hasRole(LibAuthoriserInvariants.DEFAULT_ADMIN_ROLE, RETIRED_SIGNER),
            "RevokeFireblocksServiceSigner: retired signer holds DEFAULT_ADMIN_ROLE"
        );
    }

    /// @notice Author the revocation bundle for the active chain: see the
    /// contract-level flow. Does not broadcast — execution happens via the
    /// Safe UI using the emitted artifact.
    function run() external {
        // --- Pre-flight ---------------------------------------------------

        address safeAddr = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        IGnosisSafe safe = IGnosisSafe(safeAddr);

        address authoriser = activeChainAuthoriser();
        IAccessControl acl = IAccessControl(authoriser);

        // --- Build the bundle ----------------------------------------------

        (RoleGrant[] memory retired, SafeTx[] memory txs) = authorBundle(authoriser, safeAddr);

        // The whole bundle executes as ONE MultiSend at this nonce, so the
        // canonical MultiSend `SafeTxHash` is the hash the Safe UI shows
        // signers — a per-inner-tx hash never appears there once the Tx
        // Builder batches the import.
        uint256 nonce = safe.nonce();
        bytes32 bundleSafeTxHash = LibSafeOps.computeMultiSendSafeTxHash(safe, txs, nonce);

        // --- Simulate -----------------------------------------------------

        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(safe, txs[i].to, txs[i].data);
        }

        // --- Post-state ---------------------------------------------------

        // The retired signer holds nothing; every other row of the canonical
        // map is untouched; the Safe identity + threshold are unchanged.
        assertPostRevocationState(acl, safeAddr);
        LibSafeInvariants.assertImmutableInvariants(safe);
        LibSafeInvariants.assertThreshold(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        // --- Artifact -----------------------------------------------------

        string memory json = LibSafeOps.emitTxBuilderJson(safeAddr, block.chainid, BUNDLE_NAME, txs);
        vm.writeFile(artifactPath(), json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("Bundle MultiSend SafeTxHash:", vm.toString(bundleSafeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Bundle item count:", txs.length);
        console2.log("Chain:", block.chainid);
        console2.log("Authoriser:", authoriser);
        console2.log("Retired signer:", RETIRED_SIGNER);

        // --- n+1 reversal proof --------------------------------------------

        // The revocation is fully reversible (re-grant sits under the same
        // `_ADMIN` the Safe holds). Prove the re-grant clears the live
        // threshold on the first role, then revoke again so the fork ends
        // revoked.
        LibSafeOps.simulateNPlus1(
            safe,
            authoriser,
            abi.encodeCall(IAccessControl.grantRole, (retired[0].role, retired[0].grantee)),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
        );
        require(
            acl.hasRole(retired[0].role, retired[0].grantee),
            "RevokeFireblocksServiceSigner: n+1 re-grant did not restore the role"
        );
        LibSafeOps.simulateExternalCall(
            safe, authoriser, abi.encodeCall(IAccessControl.revokeRole, (retired[0].role, retired[0].grantee))
        );
        console2.log("n+1 reversal check passed: the Safe can re-grant (and re-revoke) under the live threshold");
    }

    /// @notice Signer-side integrity check for a CI-authored revocation
    /// artifact, run LOCALLY against a live fork before signing: re-runs
    /// the pre-flight and grant-map drift guard, re-derives the revoke
    /// bundle from CURRENT live chain state, asserts the artifact at
    /// `jsonPath` matches it byte-exactly (shared
    /// `LibSafeOps.assertParsedTxsMatch`), and logs the canonical MultiSend
    /// `SafeTxHash` at the live nonce for the Safe-UI cross-check. Any
    /// drift between authoring and signing — a nonce bump, a pair already
    /// revoked, a stale or tampered artifact — surfaces as a typed
    /// mismatch before anyone signs. Deliberately NOT in the run-script
    /// dispatcher: it takes a local path and runs on the signer's machine.
    /// @param jsonPath Filesystem path to the downloaded Tx Builder JSON.
    function verify(string calldata jsonPath) external view {
        address safeAddr = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        IGnosisSafe safe = IGnosisSafe(safeAddr);
        address authoriser = activeChainAuthoriser();

        (, SafeTx[] memory expected) = authorBundle(authoriser, safeAddr);
        LibSafeOps.assertParsedTxsMatch(expected, jsonPath);

        uint256 nonce = safe.nonce();
        console2.log("Artifact verified against live state.");
        console2.log(
            "Bundle MultiSend SafeTxHash:", vm.toString(LibSafeOps.computeMultiSendSafeTxHash(safe, expected, nonce))
        );
        console2.log("Nonce:", nonce);
    }
}
