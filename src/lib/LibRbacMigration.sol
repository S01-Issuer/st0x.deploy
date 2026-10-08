// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibRbacMigration
/// @notice The migration registry keys for ST0x role changes. One namespace
/// covers all RBAC tracking, so every role change the token-owner Safe makes
/// lands in one ordered line rather than a namespace per contract. Each change
/// is its own migration id under it.
library LibRbacMigration {
    /// @notice The line the token-owner Safe records every RBAC change under.
    bytes32 internal constant STOX_RBAC_NAMESPACE = keccak256("st0x.rbac");

    /// @notice Applying the EU assets authoriser's pinned role map and handing
    /// the seven `_ADMIN` roles to the governance timelock.
    bytes32 internal constant EU_AUTHORISER_GRANT_AND_HANDOVER =
        keccak256("st0x.rbac.eu-assets-authoriser.grant-and-handover");
}
