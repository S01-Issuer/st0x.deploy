// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @notice A contract of the audited 0.1.30 closure has no runtime code at
/// its pinned address on the active chain. Ship the closure first via
/// `manual-sol-artifacts-0-1-30.yaml`.
/// @param pinned The pinned closure address that is missing.
error ClosureNotDeployed(address pinned);

/// @notice A closure contract's runtime codehash does not match its 0.1.30
/// pin — something other than the audited bytecode sits at the pinned
/// address.
/// @param pinned The pinned closure address inspected.
/// @param expected The pinned 0.1.30 codehash.
/// @param actual The codehash read from the chain.
error ClosureCodehashMismatch(address pinned, bytes32 expected, bytes32 actual);

/// @title LibClosureInvariants
/// @notice The "audited contract is live at its pin" gate every script that
/// depends on the 0.1.30 closure runs in pre-flight.
library LibClosureInvariants {
    /// @notice Assert one closure contract is live at its pin with the
    /// audited codehash.
    /// @param pinned The pinned closure address.
    /// @param codehash The pinned codehash.
    function assertClosureContract(address pinned, bytes32 codehash) internal view {
        if (pinned.code.length == 0) {
            revert ClosureNotDeployed(pinned);
        }
        if (pinned.codehash != codehash) {
            revert ClosureCodehashMismatch(pinned, codehash, pinned.codehash);
        }
    }
}
