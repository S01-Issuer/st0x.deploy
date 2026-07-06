// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IGnosisSafe} from "../interface/IGnosisSafe.sol";
import {LibAuthoriserInvariants} from "./LibAuthoriserInvariants.sol";
import {LibChainPrincipals, ChainPrincipals} from "./LibChainPrincipals.sol";
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
    /// (`LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE`) until
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
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE,
            LibProdDeployV4.V4_SWAP_DEADLINE
        );
        LibAuthoriserInvariants.assertAll();
    }

    /// @notice Chain-parametric full-production-state pre-flight — the
    /// multichain generalisation of `assertAll(safe)`. Asserts, for the
    /// supplied chain: the Safe-side invariants (identity + config + owner
    /// set + threshold), the token-side uniformity (every vault in `tokens`
    /// owned by `safe` and gated by the single `authoriser`), and the
    /// authoriser's role-grant map for that chain's `principals`. Every
    /// chain-specific input is a parameter, so the same call pre-flights
    /// Ethereum OR any future chain.
    ///
    /// @dev Unlike Base's `assertAll(safe)` this asserts a SINGLE uniform
    /// authoriser rather than the V4 swap-window pair: a bootstrap chain is
    /// deployed directly at V4 with its vaults wired onto one clone from the
    /// start, so there is no V3→V4 migration window to tolerate. The ST0x
    /// token-owner Safe is reproduced at the same address with the same owner
    /// set + threshold on every chain (see `LibChainPrincipals`), so the
    /// Safe-side leg uses the shared no-arg `LibSafeInvariants.assertAll(safe)`
    /// pins on every chain. The authoriser CODEHASH is not asserted here (a
    /// deploy-artifact property the clone-deploy script + cross-chain parity
    /// pin check against `LibProdDeployV4`); this bundle asserts live ROLE
    /// state + ownership.
    /// @param safe The chain's token-owner Safe.
    /// @param tokens The chain's production token table.
    /// @param authoriser The chain's live authoriser the vaults point at.
    /// @param principals The chain's principals, supplying the expected
    /// role-grant grantees.
    function assertProductionState(
        IGnosisSafe safe,
        TokenInstance[] memory tokens,
        address authoriser,
        ChainPrincipals memory principals
    ) internal view {
        LibSafeInvariants.assertAll(safe);
        LibTokenInvariants.assertAll(tokens, address(safe), authoriser);
        LibAuthoriserInvariants.assertExpectedGrants(authoriser, principals);
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
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE,
            LibProdDeployV4.V4_SWAP_DEADLINE
        );
        LibAuthoriserInvariants.assertAll();
    }
}
