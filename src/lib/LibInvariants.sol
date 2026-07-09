// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IGnosisSafe} from "../interface/IGnosisSafe.sol";
import {LibAuthoriserInvariants} from "./LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "./LibProdDeployV4.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibTokenInvariants} from "./LibTokenInvariants.sol";

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
    /// @notice Full production-state invariant bundle. Composes every
    /// per-facet `assertAll`: Safe identity / config + token-side
    /// owner/authoriser uniformity. Pre-flight at the start of every
    /// migration script and prod-state fork test; if this passes silently
    /// the live system is in its current expected state across every
    /// pinned facet.
    /// @dev The full-args overload is the right call site only when a
    /// caller is *deliberately* asserting a state that diverges from the
    /// pinned current truth (e.g. a migration script's post-state re-check
    /// after it has simulated `changeThreshold`); the no-arg overload
    /// fills in the `LibSafeInvariants`-pinned defaults.
    ///
    /// The authoriser leg is migration-window gated for the V4 swap:
    /// every vault's `authorizer()` may be the V3 authoriser
    /// (`LibAuthoriserInvariants.STOX_PROD_AUTHORISER`) or the V4 clone
    /// (`LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE`) until
    /// `LibProdDeployV4.V4_SWAP_DEADLINE`; only the V4 clone after. This
    /// keeps the bundle green across the swap with no post-execution lib
    /// repoint: before the swap the pre-state matches, after the swap the
    /// post-state matches, and past the deadline an un-run swap red-lines
    /// cron. `LibAuthoriserInvariants.assertAll()` continues to validate
    /// the V3 clone's own impl pin + grant map — properties of that
    /// contract which stay true after the swap (the swap does not revoke
    /// anything on the old clone).
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

    /// @notice Full-args bundle. Use when overriding the Safe-side
    /// threshold or owner set from `LibSafeInvariants`' current-truth pins —
    /// typically only when running a script that intentionally changes
    /// one of those (post-state assertion). The token-side and authoriser-
    /// side legs match the no-arg overload, including the V4 swap
    /// migration window on the authoriser leg.
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
