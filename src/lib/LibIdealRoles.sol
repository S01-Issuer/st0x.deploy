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
    /// @notice The V4 authoriser, EU authoriser, orchestrator, governance timelock
    /// and mint-caps orchestrator on a chain, in that order. Every timelock
    /// holder is the chain's prod governance timelock. On a chain whose
    /// authoriser grants no orchestrator (0G), the two orchestrators are left
    /// out: nothing there is expected to hold their roles.
    /// @param chainId The chain id.
    /// @return The contracts' ideal role state.
    function contractRoles(uint256 chainId) internal pure returns (ContractRoles[] memory) {
        address safe = LibSafeInvariants.safeForChainId(chainId);
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        bool orchestrated = LibAuthoriserInvariants.grantsOrchestrator(chainId);
        ContractRoles[] memory roles = new ContractRoles[](orchestrated ? 5 : 3);
        uint256 next = 0;
        roles[next++] = ContractRoles(
            LibAuthoriserInvariants.authoriserForChainId(chainId),
            LibAuthoriserInvariants.expectedGrantsOn(chainId, safe, timelock)
        );
        roles[next++] = ContractRoles(
            LibAuthoriserInvariants.euAuthoriserForChainId(chainId),
            LibAuthoriserInvariants.expectedEuGrants(
                timelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER, LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
            )
        );
        if (orchestrated) {
            roles[next++] = ContractRoles(
                LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE,
                LibOrchestratorInvariants.expectedGrants(safe, timelock)
            );
        }
        roles[next++] = ContractRoles(timelock, LibTimelockInvariants.expectedGrants(timelock, safe));
        if (orchestrated) {
            roles[next++] = ContractRoles(
                LibOrchestratorInvariants.mintCapsInstance(), LibOrchestratorInvariants.mintCapsExpectedGrants(timelock)
            );
        }
        return roles;
    }
}
