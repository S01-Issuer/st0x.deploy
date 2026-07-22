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
///
/// Until the address is pinned the check is PENDING (logged loudly, not a
/// silent skip): there is no live Safe to assert against yet.
///
/// @dev SECOND pending gate: the shared rainix test workflow declares a
/// fixed RPC secret set with no HyperEVM slot, so `HYPEREVM_RPC_URL` is
/// absent in CI until rainix grows one (or this repo runs a local test
/// job). The env guard logs loudly rather than failing the fork setup;
/// remove it once CI carries the secret so a missing RPC becomes a hard
/// failure instead of a skip.
contract HyperEvmTokenOwnerSafeParityTest is Test {
    /// The pinned HyperEVM Safe carries the shared token-owner policy in
    /// every way that matters, and is a distinct address from the other
    /// chains' Safes.
    function testHyperEvmSafeMatchesSharedPolicy() external {
        address hyperevmSafe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM;

        if (hyperevmSafe == address(0)) {
            emit log("PENDING: HyperEVM token-owner Safe address not yet pinned - hydrate STOX_TOKEN_OWNER_SAFE_HYPEREVM (RAI-1511)");
            return;
        }

        if (bytes(vm.envOr("HYPEREVM_RPC_URL", string(""))).length == 0) {
            emit log("PENDING: HYPEREVM_RPC_URL not available in this environment - the shared rainix test workflow has no HyperEVM RPC secret slot yet (RAI-1511)");
            return;
        }

        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        LibSafeInvariants.assertTokenOwnerSafePolicy(IGnosisSafe(hyperevmSafe));
    }
}
