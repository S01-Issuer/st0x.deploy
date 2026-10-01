// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {IGnosisSafe} from "../../../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title RobinhoodTokenOwnerSafeParityTest
/// @notice The Robinhood Chain ST0x token-owner Safe (the same CREATE2
/// address as Ethereum's and HyperEVM's; a per-chain deployment with its own
/// state) carries the chain-agnostic token-owner policy: the same owner set
/// (order-insensitive), threshold, and v1.4.1 identity as every other
/// chain's Safe.
///
/// @dev Forks Robinhood Chain head unconditionally; needs `ROBINHOOD_RPC_URL`.
contract RobinhoodTokenOwnerSafeParityTest is Test {
    /// The pinned Robinhood Chain Safe carries the shared token-owner policy.
    function testRobinhoodSafeMatchesSharedPolicy() external {
        address robinhoodSafe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ROBINHOOD;

        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        LibSafeInvariants.assertTokenOwnerSafePolicy(IGnosisSafe(robinhoodSafe));
    }
}
