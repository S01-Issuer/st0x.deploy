// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibEuAuthoriserMigration
/// @notice The migration registry keys for the EU assets authoriser's role
/// rollout. The Safe bundle writes them and the prod tests read them to pick
/// which state to assert, so they live here rather than in either.
library LibEuAuthoriserMigration {
    /// @notice The line the token-owner Safe records the EU authoriser's
    /// migrations under.
    bytes32 internal constant EU_AUTHORISER_NAMESPACE = keccak256("st0x.eu-assets-authoriser");

    /// @notice Applying the pinned role map and handing the seven `_ADMIN`
    /// roles to the governance timelock.
    bytes32 internal constant EU_AUTHORISER_MIGRATION = keccak256("st0x.eu-assets-authoriser.grant-and-handover");
}
