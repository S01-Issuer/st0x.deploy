// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IGnosisSafe} from "../../../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title RobinhoodTokenOwnerSafeParityTest
/// @notice The Robinhood Chain ST0x token-owner Safe (the same CREATE2
/// address as Ethereum's and HyperEVM's, created through the canonical Safe
/// proxy factory with the identical initializer — a per-chain deployment
/// with its own state) must carry the chain-agnostic token-owner policy: the
/// same owner SET (order-insensitive), threshold, and v1.4.1 identity as
/// every other chain's Safe. Mirrors `HyperEvmTokenOwnerSafeParityTest`.
///
/// @dev RED until the Safe is created on Robinhood Chain and its threshold
/// raised to the shared policy's 3-of-6 (RAI-2287); green thereafter,
/// catching later policy drift. Forks unconditionally: CI supplies
/// `ROBINHOOD_RPC_URL` from the `RPC_URL_ROBINHOOD_FORK` secret, so a
/// missing RPC fails at fork time rather than passing having asserted
/// nothing.
contract RobinhoodTokenOwnerSafeParityTest is Test {
    /// The pinned Robinhood Chain Safe carries the shared token-owner policy
    /// in every way that matters.
    function testRobinhoodSafeMatchesSharedPolicy() external {
        address robinhoodSafe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ROBINHOOD;

        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        LibSafeInvariants.assertTokenOwnerSafePolicy(IGnosisSafe(robinhoodSafe));
    }
}
