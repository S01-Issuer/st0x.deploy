// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {IGnosisSafe} from "../../../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title BscTokenOwnerSafeParityTest
/// @notice The BNB Smart Chain ST0x token-owner Safe (the same CREATE2
/// address as Ethereum's, HyperEVM's and Robinhood Chain's; a per-chain
/// deployment with its own state) carries the chain-agnostic token-owner
/// policy: the same owner set (order-insensitive), threshold, and v1.4.1
/// identity as every other chain's Safe.
///
/// @dev Forks BNB Smart Chain head unconditionally; needs `BSC_RPC_URL`.
contract BscTokenOwnerSafeParityTest is Test {
    /// The pinned BNB Smart Chain Safe carries the shared token-owner policy.
    function testBscSafeMatchesSharedPolicy() external {
        address bscSafe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_BSC;

        vm.createSelectFork(LibStoxDeployNetworks.BSC);
        LibSafeInvariants.assertTokenOwnerSafePolicy(IGnosisSafe(bscSafe));
    }
}
