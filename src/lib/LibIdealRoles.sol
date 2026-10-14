// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibAuthoriserInvariants} from "./LibAuthoriserInvariants.sol";
import {LibOrchestratorInvariants} from "./LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";
import {RoleGrant} from "./RoleGrant.sol";

/// @notice One role-bearing contract's ideal role state.
/// @param target The contract.
/// @param expected The pairs it must carry.
struct ContractRoles {
    address target;
    RoleGrant[] expected;
}

/// @title LibIdealRoles
/// @notice The ideal role state of every role-bearing contract st0x runs, per chain.
library LibIdealRoles {
    /// @notice The V4 authoriser, EU authoriser, orchestrator and governance timelock on a chain, in that order.
    /// @param chainId The chain id.
    /// @return The contracts' ideal role state.
    function contractRoles(uint256 chainId) internal pure returns (ContractRoles[] memory) {
        address safe = LibSafeInvariants.safeForChainId(chainId);
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        ContractRoles[] memory roles = new ContractRoles[](4);
        roles[0] = ContractRoles(
            LibAuthoriserInvariants.authoriserForChainId(chainId),
            LibAuthoriserInvariants.expectedGrants(safe, timelock)
        );
        roles[1] = ContractRoles(
            LibAuthoriserInvariants.euAuthoriserForChainId(chainId),
            LibAuthoriserInvariants.expectedEuGrants(
                timelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER, LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
            )
        );
        roles[2] = ContractRoles(
            LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE,
            LibOrchestratorInvariants.expectedGrants(safe, timelock)
        );
        roles[3] = ContractRoles(timelock, LibTimelockInvariants.expectedGrants(timelock, safe));
        return roles;
    }
}
