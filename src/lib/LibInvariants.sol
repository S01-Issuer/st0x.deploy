// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IGnosisSafe} from "../interface/IGnosisSafe.sol";
import {LibProdSafes} from "./LibProdSafes.sol";
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
    /// fills in the `LibProdSafes`-pinned defaults.
    /// @param safe The Safe to validate against the pinned current truth.
    function assertAll(IGnosisSafe safe) internal view {
        LibSafeInvariants.assertAll(safe);
        LibTokenInvariants.assertAll(address(safe));
    }

    /// @notice Full-args bundle. Use when overriding the Safe-side
    /// threshold or owner set from `LibProdSafes`' current-truth pins —
    /// typically only when running a script that intentionally changes
    /// one of those (post-state assertion). The token-side leg always
    /// uses the pinned defaults (vault ownership against the Safe,
    /// authoriser against `LibProdTokensBase.PROD_RECEIPT_VAULT_AUTHORISER`).
    /// @param safe The Safe to validate.
    /// @param expectedThreshold The expected signature threshold.
    /// @param expectedOwners The expected owner set in `getOwners()` order.
    function assertAll(IGnosisSafe safe, uint256 expectedThreshold, address[] memory expectedOwners) internal view {
        LibSafeInvariants.assertAll(safe, expectedThreshold, expectedOwners);
        LibTokenInvariants.assertAll(address(safe));
    }
}
