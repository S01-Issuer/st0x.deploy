// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

import {LibAuthoriserInvariants} from "./LibAuthoriserInvariants.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";

/// @notice The service signer still holds `role` after the revoke executed.
/// @param role The role.
error ServiceSignerStillHoldsRole(bytes32 role);

/// @title LibServiceSignerRevoke
/// @notice The timelock batch revoking `DEPOSIT` and `WITHDRAW` from the
/// service signer on the chain's authoriser.
library LibServiceSignerRevoke {
    bytes32 internal constant SALT = keccak256("st0x.revoke-service-signer-deposit-withdraw");

    /// @param chainId The chain id.
    /// @return targets The authoriser, twice.
    /// @return values Zero, twice.
    /// @return payloads The two `revokeRole` calls.
    function batch(uint256 chainId)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        address authoriser = LibAuthoriserInvariants.authoriserForChainId(chainId);
        targets = new address[](2);
        targets[0] = authoriser;
        targets[1] = authoriser;
        values = new uint256[](2);
        payloads = new bytes[](2);
        payloads[0] = abi.encodeCall(
            IAccessControl.revokeRole, (keccak256("DEPOSIT"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C)
        );
        payloads[1] = abi.encodeCall(
            IAccessControl.revokeRole, (keccak256("WITHDRAW"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C)
        );
    }

    /// @param timelock The timelock.
    /// @param chainId The chain id.
    /// @return The batch's operation id.
    function operationId(address timelock, uint256 chainId) internal view returns (bytes32) {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch(chainId);
        return TimelockController(payable(timelock)).hashOperationBatch(targets, values, payloads, bytes32(0), SALT);
    }

    /// @param chainId The chain id.
    /// @return The `scheduleBatch` calldata.
    function scheduleCalldata(uint256 chainId) internal pure returns (bytes memory) {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch(chainId);
        return abi.encodeCall(
            TimelockController.scheduleBatch,
            (targets, values, payloads, bytes32(0), SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
        );
    }

    /// @notice Reverts unless the service signer holds neither role.
    /// @param authoriser The authoriser.
    function assertRevoked(address authoriser) internal view {
        address signer = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        if (IAccessControl(authoriser).hasRole(keccak256("DEPOSIT"), signer)) {
            revert ServiceSignerStillHoldsRole(keccak256("DEPOSIT"));
        }
        if (IAccessControl(authoriser).hasRole(keccak256("WITHDRAW"), signer)) {
            revert ServiceSignerStillHoldsRole(keccak256("WITHDRAW"));
        }
    }
}
