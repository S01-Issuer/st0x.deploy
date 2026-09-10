// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IGnosisSafe} from "../../../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title BscTokenOwnerSafeParityTest
/// @notice The BNB Smart Chain ST0x token-owner Safe (the same CREATE2
/// address as Ethereum's, HyperEVM's and Robinhood Chain's, created through the canonical Safe
/// proxy factory with the identical initializer — a per-chain deployment
/// with its own state) must carry the chain-agnostic token-owner policy: the
/// same owner SET (order-insensitive), threshold, and v1.4.1 identity as
/// every other chain's Safe. Mirrors `RobinhoodTokenOwnerSafeParityTest`.
///
/// @dev RED until the Safe is created on BNB Smart Chain and its threshold
/// raised to the shared policy's 3-of-6 (RAI-2287, BNB row); green thereafter,
/// catching later policy drift. Forks unconditionally: CI supplies
/// `BSC_RPC_URL` from the `RPC_URL_BSC_FORK` secret, so a
/// missing RPC fails at fork time rather than passing having asserted
/// nothing.
contract BscTokenOwnerSafeParityTest is Test {
    /// The pinned BNB Smart Chain Safe carries the shared token-owner policy
    /// in every way that matters.
    function testBscSafeMatchesSharedPolicy() external {
        address bscSafe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_BSC;

        vm.createSelectFork(LibStoxDeployNetworks.BSC);
        LibSafeInvariants.assertTokenOwnerSafePolicy(IGnosisSafe(bscSafe));
    }
}
