// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";

import {RetireDirectSignerRoles} from "../../script/20260831-retire-direct-signer-roles.s.sol";
import {SafeTx} from "../../src/lib/LibSafeOps.sol";

/// @dev Exposes the script's internals so the guard tests can drive them
/// directly.
contract RetireDirectSignerRolesHarness is RetireDirectSignerRoles {
    /// @notice The script's `assertOrchestratorPathEnabled()`, externally
    /// callable.
    function callAssertOrchestratorPathEnabled(IAccessControl acl, address orchestrator) external view {
        assertOrchestratorPathEnabled(acl, orchestrator);
    }

    /// @notice The script's `authorBundle()`, externally callable.
    function callAuthorBundle(address authoriser, address safeAddr) external view returns (SafeTx[] memory) {
        return authorBundle(authoriser, safeAddr);
    }
}
