// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @notice No name in `LibRoleNames` hashes to this role.
/// @param role The role.
error UnnamedRole(bytes32 role);

/// @title LibRoleNames
/// @notice The name of every role this repo grants or expects. Every role but
/// OpenZeppelin's `DEFAULT_ADMIN_ROLE` (`bytes32(0)`) is `keccak256` of its
/// name, so a name either hashes to its role or is not its name.
library LibRoleNames {
    /// @notice The name of `role`; reverts `UnnamedRole` for a role no name
    /// here hashes to.
    /// @param role The role.
    /// @return The name.
    function nameOf(bytes32 role) internal pure returns (string memory) {
        if (role == bytes32(0)) return "DEFAULT_ADMIN_ROLE";
        string[20] memory names = [
            "DEPOSIT",
            "WITHDRAW",
            "CERTIFY",
            "CONFISCATE_SHARES",
            "CONFISCATE_RECEIPT",
            "SCHEDULE_CORPORATE_ACTION",
            "CANCEL_CORPORATE_ACTION",
            "DEPOSIT_ADMIN",
            "WITHDRAW_ADMIN",
            "CERTIFY_ADMIN",
            "CONFISCATE_SHARES_ADMIN",
            "CONFISCATE_RECEIPT_ADMIN",
            "SCHEDULE_CORPORATE_ACTION_ADMIN",
            "CANCEL_CORPORATE_ACTION_ADMIN",
            "MINT",
            "BURN",
            "EMERGENCY",
            "PROPOSER_ROLE",
            "EXECUTOR_ROLE",
            "CANCELLER_ROLE"
        ];
        for (uint256 i = 0; i < names.length; i++) {
            if (keccak256(bytes(names[i])) == role) return names[i];
        }
        revert UnnamedRole(role);
    }
}
