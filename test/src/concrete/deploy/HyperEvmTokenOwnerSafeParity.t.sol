// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IGnosisSafe} from "../../../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title HyperEvmTokenOwnerSafeParityTest
/// @notice The HyperEVM ST0x token-owner Safe (deliberately the same
/// CREATE2 address as Ethereum's, created through the canonical Safe proxy
/// factory — a per-chain deployment with its own state) must carry the
/// chain-agnostic token-owner policy: the same owner SET
/// (order-insensitive), threshold, and v1.4.1 identity as every other
/// chain's Safe. Mirrors `EthereumTokenOwnerSafeParityTest`.
contract HyperEvmTokenOwnerSafeParityTest is Test {
    /// The pinned HyperEVM Safe carries the shared token-owner policy in
    /// every way that matters, at the same address as Ethereum's Safe —
    /// the canonical Safe proxy factory with the same initializer yields
    /// the same CREATE2 address on both chains.
    function testHyperEvmSafeMatchesSharedPolicy() external {
        address hyperevmSafe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM;

        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        LibSafeInvariants.assertTokenOwnerSafePolicy(IGnosisSafe(hyperevmSafe));
    }
}
