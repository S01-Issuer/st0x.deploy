// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibRbacMigration
/// @notice The migration registry keys for ST0x role changes. One namespace
/// covers all RBAC tracking rather than a namespace per contract; each writer
/// (the token-owner Safe, or the governance timelock for a change it executes)
/// has its own ordered line in it. Each change is its own migration id.
library LibRbacMigration {
    /// @notice The namespace every RBAC change is recorded under, by the Safe or
    /// the timelock, whichever performs it.
    bytes32 internal constant STOX_RBAC_NAMESPACE = keccak256("st0x.rbac");

    /// @notice Applying the EU assets authoriser's pinned role map and handing
    /// the seven `_ADMIN` roles to the governance timelock.
    bytes32 internal constant EU_AUTHORISER_GRANT_AND_HANDOVER =
        keccak256("st0x.rbac.eu-assets-authoriser.grant-and-handover");

    /// @notice Revoking the service signer's direct `DEPOSIT` and `WITHDRAW` on
    /// the production authoriser, through the governance timelock.
    bytes32 internal constant SERVICE_SIGNER_DIRECT_ROLES_RETIRED =
        keccak256("st0x.rbac.service-signer.direct-roles-retired");
}
