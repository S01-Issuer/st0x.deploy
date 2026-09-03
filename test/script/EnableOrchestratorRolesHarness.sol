// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {EnableOrchestratorRoles} from "../../script/20260831-enable-orchestrator-roles.s.sol";
import {SafeTx} from "../../src/lib/LibSafeOps.sol";

/// @dev Exposes the script's internals so the guard tests can drive them
/// directly.
contract EnableOrchestratorRolesHarness is EnableOrchestratorRoles {
    /// @notice The script's `assertFleetUpgraded()`, externally callable.
    function callAssertFleetUpgraded() external view {
        assertFleetUpgraded();
    }

    /// @notice The script's `authorBundle()`, externally callable.
    function callAuthorBundle(address authoriser, address orchestrator, address safeAddr)
        external
        view
        returns (SafeTx[] memory)
    {
        return authorBundle(authoriser, orchestrator, safeAddr);
    }

    /// @notice The script's `activeChainAuthoriser()`, externally callable.
    function callActiveChainAuthoriser() external view returns (address) {
        return activeChainAuthoriser();
    }
}
