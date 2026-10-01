// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {IGnosisSafe} from "../../../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title EthereumTokenOwnerSafeParityTest
/// @notice The Ethereum ST0x token-owner Safe
/// (`LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM`) is a distinct
/// per-chain address from Base's and carries the shared token-owner policy:
/// the v1.4.1 identity (proxy/singleton codehash, version, no modules/guard,
/// pinned fallback handler), the same owner set (order-insensitive), and the
/// same threshold.
contract EthereumTokenOwnerSafeParityTest is Test {
    /// The pinned Ethereum Safe carries the shared policy and is a distinct
    /// address from Base's Safe.
    function testEthereumSafeMatchesBasePolicy() external {
        address ethSafe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM;

        // Guards against a copy-paste of Base's address into the Ethereum pin.
        assertTrue(
            ethSafe != LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,
            "Ethereum Safe pin must be a distinct per-chain address, not Base's"
        );

        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);

        // Base is asserted against the same pins, so this is parity with Base.
        LibSafeInvariants.assertTokenOwnerSafePolicy(IGnosisSafe(ethSafe));
    }
}
