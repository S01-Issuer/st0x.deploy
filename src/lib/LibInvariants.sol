// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IGnosisSafe} from "../interface/IGnosisSafe.sol";
import {LibAuthoriserInvariants} from "./LibAuthoriserInvariants.sol";
import {LibProdAuthoriserClones} from "./LibProdAuthoriserClones.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "./LibTokenInvariants.sol";

/// @title LibInvariants
/// @notice Orchestrator that composes every per-facet `assertAll` into a
/// single bundle. Each facet lib (`LibSafeInvariants`, `LibTokenInvariants`,
/// any future `Lib<Subject>Invariants`) owns its own `assertAll`; this lib
/// chains them so a consumer asserting the full production state has a
/// single call site without any facet lib having to know about other
/// facets.
/// @dev Lives separately from `LibSafeInvariants` so the file name doesn't
/// lie about scope: cross-facet composition belongs in a cross-facet lib,
/// not inside a Safe-named lib. Per-facet libs stay focused on their
/// subject and reachable standalone for scripts / fork tests that don't
/// need the full bundle.
library LibInvariants {
    /// @notice Full production-state invariant bundle for **Base**. Composes
    /// every per-facet `assertAll`: Safe identity / config + token-side
    /// owner/authoriser uniformity. Pre-flight at the start of every
    /// migration script and prod-state fork test; if this passes silently
    /// the live system is in its current expected state across every
    /// pinned facet.
    ///
    /// The authoriser leg is migration-window gated for the V4 swap: every
    /// vault's `authorizer()` may be the V3 authoriser
    /// (`LibAuthoriserInvariants.STOX_PROD_AUTHORISER`) or the V4 clone
    /// (`LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_BASE`) until
    /// `LibProdDeployV4.V4_SWAP_DEADLINE`; only the V4 clone after. This keeps
    /// the bundle green across the swap with no post-execution lib repoint:
    /// before the swap the pre-state matches, after the swap the post-state
    /// matches, and past the deadline an un-run swap red-lines cron.
    /// `LibAuthoriserInvariants.assertAll()` continues to validate the V3
    /// clone's own impl pin + grant map.
    ///
    /// @dev The chain-agnostic generalisation used for other chains is
    /// `assertProductionState`. Base keeps this dedicated overload because
    /// the V4 swap window is a Base-only transitional concern — a bootstrap
    /// chain deploys directly at V4 with a single authoriser and no window.
    /// @param safe The Safe to validate against the pinned current truth.
    function assertAll(IGnosisSafe safe) internal view {
        LibSafeInvariants.assertAll(safe);
        LibTokenInvariants.assertUniformOwnership(address(safe));
        LibTokenInvariants.assertUniformAuthoriserMigration(
            LibAuthoriserInvariants.STOX_PROD_AUTHORISER,
            LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_BASE,
            LibProdDeployV4.V4_SWAP_DEADLINE
        );
        LibAuthoriserInvariants.assertAll();
    }

    /// @notice Multichain full-production-state pre-flight — the
    /// chain-agnostic generalisation of `assertAll(safe)`. Asserts, for the
    /// ACTIVE chain (`block.chainid`): the Safe carries the chain-agnostic
    /// token-owner policy (`assertTokenOwnerSafePolicy` — v1.4.1 identity,
    /// owner SET, threshold), the token-side uniformity (every vault in
    /// `tokens` owned by that chain's Safe and gated by the single
    /// `authoriser`), and the authoriser's role-grant map for that chain's
    /// Safe. The Safe is resolved AND policy-asserted in one call via
    /// `LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid)`,
    /// so the deploy artifacts that differ per chain — the Safe address, the
    /// token addresses, the authoriser clone address — are the only variation.
    ///
    /// @dev The Safe POLICY (owner set, threshold, v1.4.1 identity) and the
    /// service signer are SHARED across chains; only the ADDRESSES differ. The
    /// Safe address is therefore a per-chain deploy artifact (not a principal):
    /// resolved by chain id, and its policy asserted against the shared pins.
    /// The owner check is order-INSENSITIVE because a per-chain Safe's
    /// `getOwners()` order is incidental. There is no `ChainPrincipals`
    /// parameter — the per-chain inputs are the token addresses and the
    /// authoriser clone address (whose impl codehash is asserted equal across
    /// chains by the cross-chain parity pin); the Safe address is read from
    /// the per-chain pin here.
    ///
    /// Unlike Base's `assertAll(safe)` this asserts a SINGLE uniform
    /// authoriser rather than the V4 swap-window pair: a bootstrap chain is
    /// deployed directly at V4 with its vaults wired onto one clone from the
    /// start, so there is no V3→V4 migration window to tolerate. The
    /// authoriser CODEHASH is not asserted here (a deploy-artifact property
    /// the clone-deploy script + cross-chain parity pin check); this bundle
    /// asserts live ROLE state + ownership.
    /// @param tokens The chain's production token table.
    /// @param authoriser The chain's live authoriser the vaults point at.
    function assertProductionState(TokenInstance[] memory tokens, address authoriser) internal view {
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTokenInvariants.assertAll(tokens, safe, authoriser);
        LibAuthoriserInvariants.assertExpectedGrants(authoriser, safe);
    }

    /// @notice Full-args Base bundle. Use when overriding the Safe-side
    /// threshold or owner set from `LibSafeInvariants`' current-truth pins —
    /// typically only when running a script that intentionally changes one of
    /// those (post-state assertion). The token-side and authoriser-side legs
    /// match the no-arg overload, including the V4 swap migration window on
    /// the authoriser leg.
    /// @param safe The Safe to validate.
    /// @param expectedThreshold The expected signature threshold.
    /// @param expectedOwners The expected owner set in `getOwners()` order.
    function assertAll(IGnosisSafe safe, uint256 expectedThreshold, address[] memory expectedOwners) internal view {
        LibSafeInvariants.assertAll(safe, expectedThreshold, expectedOwners);
        LibTokenInvariants.assertUniformOwnership(address(safe));
        LibTokenInvariants.assertUniformAuthoriserMigration(
            LibAuthoriserInvariants.STOX_PROD_AUTHORISER,
            LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_BASE,
            LibProdDeployV4.V4_SWAP_DEADLINE
        );
        LibAuthoriserInvariants.assertAll();
    }
}
