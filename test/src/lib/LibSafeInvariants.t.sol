// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibLocalProdState} from "../../lib/LibLocalProdState.sol";

/// @title LibSafeInvariantsTest
/// @notice The ST0x token-owner Safe's pins: every factory-derived pin equals
/// the derivation from the pinned initializer, and the chain-id lookup
/// resolves Base and Ethereum to their own pins.
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
        assertEq(LibSafeInvariants.safeForChainId(LibSafeInvariants.ZEROG_CHAIN_ID), derived, "zerog");
        assertNotEq(LibSafeInvariants.safeForChainId(LibSafeInvariants.BASE_CHAIN_ID), derived, "base");
    }

    function testSafeForChainIdResolvesBaseAndEthereumPins() external pure {
        assertEq(
            LibSafeInvariants.safeForChainId(LibSafeInvariants.BASE_CHAIN_ID),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,
            "base"
        );
        assertEq(
            LibSafeInvariants.safeForChainId(LibSafeInvariants.ETHEREUM_CHAIN_ID),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM,
            "ethereum"
        );
    }

    /// @notice Every chain's Safe built at its pin in the policy passes the
    /// policy assertion.
    function testTokenOwnerSafePolicyHoldsOnEveryChain() external {
        uint256[] memory chainIds = LibLocalProdState.chainIds();
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 snapshot = vm.snapshotState();
            Safe safe = LibLocalProdState.safe(vm, chainIds[i], LibSafeInvariants.expectedOwners());
            LibSafeInvariants.assertTokenOwnerSafePolicy(safe);
            vm.revertToState(snapshot);
        }
    }

    /// @notice The owner check is a set check: a Safe listing the owners in
    /// creation order rather than `expectedOwners()` order still passes.
    function testTokenOwnerSafePolicyAcceptsCreationOwnerOrder() external {
        uint256[] memory chainIds = LibLocalProdState.chainIds();
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 snapshot = vm.snapshotState();
            Safe safe = LibLocalProdState.safe(vm, chainIds[i], LibSafeInvariants.tokenOwnerSafeCreationOwners());
            assertNotEq(safe.getOwners()[0], LibSafeInvariants.expectedOwners()[0], "owner order differs");
            LibSafeInvariants.assertTokenOwnerSafePolicy(safe);
            vm.revertToState(snapshot);
        }
    }

    /// @notice On every chain the active-chain entry point asserts that
    /// chain's Safe and returns its pin.
    function testActiveChainTokenOwnerSafeReturnsTheChainPin() external {
        uint256[] memory chainIds = LibLocalProdState.chainIds();
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 snapshot = vm.snapshotState();
            vm.chainId(chainIds[i]);
            LibLocalProdState.safe(vm, chainIds[i], LibSafeInvariants.expectedOwners());
            assertEq(
                LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid),
                LibSafeInvariants.safeForChainId(chainIds[i])
            );
            vm.revertToState(snapshot);
        }
    }

    /// @notice The 0G chain id is the one the `rain-deploy` catalogue gives
    /// the `zerog` network, under both this repo's name and `rain-deploy`'s.
    function testZerogChainIdIsTheCatalogueChainId() external pure {
        string[] memory names = new string[](2);
        names[0] = LibStoxDeployNetworks.ZEROG;
        names[1] = LibRainDeploy.ZEROG;
        SupportedNetwork[] memory configs = LibRainDeploy.declaredNetworkConfigs(names);
        assertEq(configs[0].chainId, LibSafeInvariants.ZEROG_CHAIN_ID, "st0x name");
        assertEq(configs[1].chainId, LibSafeInvariants.ZEROG_CHAIN_ID, "rain-deploy name");
    }
}
