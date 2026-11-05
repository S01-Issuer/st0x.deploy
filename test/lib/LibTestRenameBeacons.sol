// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";

import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @title LibTestRenameBeacons
/// @notice What a head-fork test expects a chain's receipt-vault and wrapper
/// beacons to serve while the rename rollout is in flight. Each chain runs the
/// beacon batch on its own schedule, so at head one chain can serve the
/// implementation the batch moves from and another the one it moves to. Both
/// are pinned; anything else still fails.
library LibTestRenameBeacons {
    /// @return The implementation `beacon` should serve: the rollout target
    /// if it already serves it, else the pinned from-implementation.
    function receiptVaultImplementation(address beacon) internal view returns (address) {
        return pick(
            IBeacon(beacon).implementation(),
            LibUnderlyingNamingRollout.RECEIPT_VAULT_FROM_IMPLEMENTATION,
            LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION
        );
    }

    /// @return The implementation `beacon` should serve: the rollout target
    /// if it already serves it, else the pinned from-implementation.
    function wrappedTokenVaultImplementation(address beacon) internal view returns (address) {
        return pick(
            IBeacon(beacon).implementation(),
            LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_FROM_IMPLEMENTATION,
            LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_IMPLEMENTATION
        );
    }

    /// @return Whether two chains' receipt-vault beacon implementations agree,
    /// or each is one of the rollout's two pinned receipt-vault
    /// implementations (the chains are at different rollout steps).
    function receiptVaultImplementationsAgree(address a, address b) internal pure returns (bool) {
        return a == b || (isReceiptVaultRolloutStep(a) && isReceiptVaultRolloutStep(b));
    }

    function isReceiptVaultRolloutStep(address implementation) internal pure returns (bool) {
        return implementation == LibUnderlyingNamingRollout.RECEIPT_VAULT_FROM_IMPLEMENTATION
            || implementation == LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION;
    }

    function pick(address actual, address from, address target) private pure returns (address) {
        return actual == target ? target : from;
    }
}
