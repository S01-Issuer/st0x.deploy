// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {IGnosisSafe} from "../../../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title HyperEvmTokenOwnerSafeParityTest
/// @notice The HyperEVM ST0x token-owner Safe (the same CREATE2 address as
/// Ethereum's; a per-chain deployment with its own state) carries the
/// chain-agnostic token-owner policy: the same owner set
/// (order-insensitive), threshold, and v1.4.1 identity as every other
/// chain's Safe.
contract HyperEvmTokenOwnerSafeParityTest is Test {
    /// The pinned HyperEVM Safe carries the shared token-owner policy.
    function testHyperEvmSafeMatchesSharedPolicy() external {
        address hyperevmSafe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM;

        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        LibSafeInvariants.assertTokenOwnerSafePolicy(IGnosisSafe(hyperevmSafe));
    }
}
