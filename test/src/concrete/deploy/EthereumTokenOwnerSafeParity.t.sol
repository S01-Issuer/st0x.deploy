// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IGnosisSafe} from "../../../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title EthereumTokenOwnerSafeParityTest
/// @notice The Ethereum ST0x token-owner Safe is a **distinct per-chain
/// address** — the matched-address reproduction was abandoned; the Safe is
/// deployed out-of-band as a clean v1.4.1 Safe with the same owner set +
/// threshold + policy as Base, and its address is pinned in
/// `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM` once deployed. This suite
/// is the forcing function that asserts the pinned Ethereum Safe matches Base
/// **in every way that matters, now and into the future**: the v1.4.1 identity
/// (proxy/singleton codehash, version, no modules/guard, pinned fallback
/// handler), the same owner SET (order-insensitive), and the same threshold —
/// all against the shared `LibSafeInvariants` policy pins, which are Base's
/// current truth. It runs in CI (including the scheduled parity workflow), so a
/// future divergence — Base rotates an owner, the Ethereum Safe is reconfigured
/// — turns it red until the two match again.
///
/// Until the address is pinned the check is PENDING (logged loudly, not a
/// silent skip): there is no live Safe to assert against yet.
contract EthereumTokenOwnerSafeParityTest is Test {
    /// The pinned Ethereum Safe carries Base's policy in every way that
    /// matters, and is a distinct address from Base's Safe.
    function testEthereumSafeMatchesBasePolicy() external {
        address ethSafe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM;

        if (ethSafe == address(0)) {
            emit log("PENDING: Ethereum token-owner Safe address not yet pinned - deploy the Safe (clean v1.4.1, Base's owners + threshold) and hydrate STOX_TOKEN_OWNER_SAFE_ETHEREUM");
            return;
        }

        // The matched-address approach was abandoned, so the Ethereum Safe must
        // be a DISTINCT per-chain address — never Base's. Guards against a
        // copy-paste of Base's address into the Ethereum pin.
        assertTrue(
            ethSafe != LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,
            "Ethereum Safe pin must be a distinct per-chain address, not Base's"
        );

        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);

        // Matches Base's policy in every way that matters: v1.4.1 identity,
        // owner set (order-insensitive), threshold.
        LibSafeInvariants.assertPolicyMatchesBase(IGnosisSafe(ethSafe));
    }
}
