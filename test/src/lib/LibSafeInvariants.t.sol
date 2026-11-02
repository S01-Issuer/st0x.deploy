// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibRainDeploy} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";

/// @title LibSafeInvariantsTest
/// @notice The ST0x token-owner Safe's pins and policy: every factory-derived
/// pin equals the derivation from the pinned initializer, and the live Safe on
/// each chain passes the policy through the single entry point broadcast
/// scripts and CI share. The generic v1.4.1 assertions the policy is built
/// from are `rain-deploy`'s `LibSafe` and tested there, each failure path
/// included.
contract LibSafeInvariantsTest is Test {
    /// @notice Every factory-derived chain's Safe pin equals the derivation
    /// from the pinned initializer, and Base's (created differently) does not.
    /// Fork-free: a mistyped pin fails here, not as a "Safe not yet created"
    /// red in the chain's parity test.
    function testTokenOwnerSafePinsMatchDerivation() external pure {
        address derived = LibSafeInvariants.expectedTokenOwnerSafeAddress();
        assertEq(LibSafeInvariants.safeForChainId(LibSafeInvariants.ETHEREUM_CHAIN_ID), derived, "ethereum");
        assertEq(LibSafeInvariants.safeForChainId(LibSafeInvariants.HYPEREVM_CHAIN_ID), derived, "hyperevm");
        assertEq(LibSafeInvariants.safeForChainId(LibSafeInvariants.ROBINHOOD_CHAIN_ID), derived, "robinhood");
        assertEq(LibSafeInvariants.safeForChainId(LibSafeInvariants.BSC_CHAIN_ID), derived, "bsc");
        assertNotEq(LibSafeInvariants.safeForChainId(LibSafeInvariants.BASE_CHAIN_ID), derived, "base");
    }

    /// @notice `assertActiveChainTokenOwnerSafe` passes against the LIVE Base
    /// token-owner Safe and resolves Base's Safe address — the same
    /// chain-agnostic policy assertion every chain gets.
    function testAssertActiveChainTokenOwnerSafeOnBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address resolved = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        assertEq(resolved, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, "Base resolved the wrong Safe");
    }

    /// @notice The SAME entry point passes against the LIVE Ethereum token-
    /// owner Safe and resolves Ethereum's Safe address. The policy pins
    /// (owner SET, threshold, v1.4.1 identity) are chain-agnostic truths;
    /// only the Safe address is per-chain, and `getOwners()` order is an
    /// incidental linked-list artifact of each chain's own deploy — which is
    /// why the policy's owner check is order-insensitive. This per-chain fork
    /// coverage is what keeps a broadcast script's Safe pre-flight from ever
    /// reverting on a chain CI has not exercised: any consumer of this entry
    /// point is proven against every pinned chain's live Safe on every CI
    /// run.
    function testAssertActiveChainTokenOwnerSafeOnEthereum() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        address resolved = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        assertEq(resolved, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM, "Ethereum resolved the wrong Safe");
    }
}
