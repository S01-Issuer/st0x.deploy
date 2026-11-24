// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

import {LibAuthoriserInvariants} from "./LibAuthoriserInvariants.sol";
import {LibOrchestratorInvariants} from "./LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";
import {RoleGrant} from "./RoleGrant.sol";

/// @notice After the batch executed, a grant it makes is not held.
/// @param target The contract.
/// @param role The role.
/// @param grantee The account.
error ZerogOrchestratorRoleNotGranted(address target, bytes32 role, address grantee);

/// @notice Before the batch is scheduled, a grant it makes is already held, so the live state is not the state the
/// batch was reviewed against.
/// @param target The contract.
/// @param role The role.
/// @param grantee The account.
error ZerogOrchestratorRoleAlreadyGranted(address target, bytes32 role, address grantee);

/// @title LibZerogOrchestratorRoles
/// @notice The 0G governance timelock batch that lets the issuance service mint and burn through the orchestrator,
/// as on every other chain: the five grants the 0G orchestrator and US authoriser lack against `LibIdealRoles`.
///
/// On the orchestrator `0x3A73…03E2` the timelock holds `DEFAULT_ADMIN_ROLE`, which administers `MINT`, `BURN` and
/// `EMERGENCY`: it grants `MINT` and `BURN` to the service signer and `EMERGENCY` to the Safe
/// (`LibOrchestratorInvariants.expectedGrants`). On the US authoriser the timelock holds `DEPOSIT_ADMIN` and
/// `WITHDRAW_ADMIN`: it grants `DEPOSIT` and `WITHDRAW` to the orchestrator (`LibAuthoriserInvariants.expectedGrants`,
/// from `ORCHESTRATOR_GRANT_INDEX`). Every other pair `LibIdealRoles` expects on 0G is already held.
library LibZerogOrchestratorRoles {
    bytes32 internal constant SALT = keccak256("st0x.zerog-orchestrator-roles");

    /// @notice The number of grants in the batch.
    uint256 internal constant GRANT_COUNT = 5;

    /// @notice The five grants, in batch order: the orchestrator's `MINT`, `BURN` and `EMERGENCY`, then the
    /// authoriser's `DEPOSIT` and `WITHDRAW`.
    /// @return targets The contract each grant is on.
    /// @return pairs The `(role, grantee)` pairs.
    function grants() internal pure returns (address[] memory targets, RoleGrant[] memory pairs) {
        uint256 chainId = LibSafeInvariants.ZEROG_CHAIN_ID;
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        address authoriser = LibAuthoriserInvariants.authoriserForChainId(chainId);
        address signer = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        targets = new address[](GRANT_COUNT);
        pairs = new RoleGrant[](GRANT_COUNT);
        targets[0] = orchestrator;
        pairs[0] = RoleGrant(keccak256("MINT"), signer);
        targets[1] = orchestrator;
        pairs[1] = RoleGrant(keccak256("BURN"), signer);
        targets[2] = orchestrator;
        pairs[2] = RoleGrant(keccak256("EMERGENCY"), LibSafeInvariants.safeForChainId(chainId));
        targets[3] = authoriser;
        pairs[3] = RoleGrant(keccak256("DEPOSIT"), LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR);
        targets[4] = authoriser;
        pairs[4] = RoleGrant(keccak256("WITHDRAW"), LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR);
    }

    /// @return targets The orchestrator three times, then the US authoriser twice.
    /// @return values Zero, five times.
    /// @return payloads The five `grantRole` calls.
    function batch()
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        RoleGrant[] memory pairs;
        (targets, pairs) = grants();
        values = new uint256[](GRANT_COUNT);
        payloads = new bytes[](GRANT_COUNT);
        for (uint256 grantIndex = 0; grantIndex < GRANT_COUNT; grantIndex++) {
            payloads[grantIndex] =
                abi.encodeCall(IAccessControl.grantRole, (pairs[grantIndex].role, pairs[grantIndex].grantee));
        }
    }

    /// @param timelock The timelock.
    /// @return The batch's operation id.
    function operationId(address timelock) internal pure returns (bytes32) {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch();
        return TimelockController(payable(timelock)).hashOperationBatch(targets, values, payloads, bytes32(0), SALT);
    }

    /// @return The `scheduleBatch` calldata, at the timelock's minimum delay.
    function scheduleCalldata() internal pure returns (bytes memory) {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch();
        return abi.encodeCall(
            TimelockController.scheduleBatch,
            (targets, values, payloads, bytes32(0), SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
        );
    }

    /// @notice Reverts unless every grant is held.
    function assertGranted() internal view {
        (address[] memory targets, RoleGrant[] memory pairs) = grants();
        for (uint256 grantIndex = 0; grantIndex < GRANT_COUNT; grantIndex++) {
            if (!IAccessControl(targets[grantIndex]).hasRole(pairs[grantIndex].role, pairs[grantIndex].grantee)) {
                revert ZerogOrchestratorRoleNotGranted(
                    targets[grantIndex], pairs[grantIndex].role, pairs[grantIndex].grantee
                );
            }
        }
    }

    /// @notice Reverts if any grant is already held.
    function assertNoneGranted() internal view {
        (address[] memory targets, RoleGrant[] memory pairs) = grants();
        for (uint256 grantIndex = 0; grantIndex < GRANT_COUNT; grantIndex++) {
            if (IAccessControl(targets[grantIndex]).hasRole(pairs[grantIndex].role, pairs[grantIndex].grantee)) {
                revert ZerogOrchestratorRoleAlreadyGranted(
                    targets[grantIndex], pairs[grantIndex].role, pairs[grantIndex].grantee
                );
            }
        }
    }
}
