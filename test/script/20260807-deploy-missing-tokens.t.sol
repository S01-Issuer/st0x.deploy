// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    DeployMissingTokens,
    DeployerNotDeployed,
    NoMissingTokens,
    UnsupportedTargetChain
} from "../../script/20260807-deploy-missing-tokens.s.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {DeployMissingTokensHarness} from "./DeployMissingTokensHarness.sol";

/// @title DeployMissingTokensTest
/// @notice Coverage for the unified token-copy script. The selection joins
/// two in-code tables (Base vs the target chain), so it is PURE — testable
/// without a fork — and the deploy pre-flight reuses the gate chain the
/// per-chain prod pins already exercise against live state.
contract DeployMissingTokensTest is Test {
    DeployMissingTokens internal script;

    function setUp() external {
        script = new DeployMissingTokens();
    }

    /// @notice A chain whose table already carries every Base underlying has
    /// nothing to copy. This is the guard that stops a re-dispatch minting
    /// duplicates of tokens that already landed.
    function testSelectionRevertsWhenTargetMatchesBase() external {
        DeployMissingTokensHarness harness = new DeployMissingTokensHarness();
        vm.expectRevert(NoMissingTokens.selector);
        harness.selectMissing(LibTokenInvariants.productionTokensBase());
    }

    /// @notice A target chain missing a Base token selects exactly that token,
    /// by `underlying`, and nothing else. Built by dropping one row from a
    /// copy of Base rather than by hardcoding a ticker, so the test does not
    /// go stale as the token set grows.
    function testSelectionPicksTheTokensTheTargetLacks() external {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        assertGt(base.length, 1, "need at least two Base tokens to drop one");

        uint256 dropped = base.length - 1;
        TokenInstance[] memory target = new TokenInstance[](base.length - 1);
        for (uint256 i = 0; i < dropped; i++) {
            target[i] = base[i];
        }

        DeployMissingTokensHarness harness = new DeployMissingTokensHarness();
        TokenConfig[] memory missing = harness.selectMissing(target);
        assertEq(missing.length, 1, "expected exactly the dropped token");
        assertEq(missing[0].underlying, base[dropped].underlying, "selected the wrong token");
    }

    /// @notice An empty target table selects the whole Base set — the
    /// bootstrap case for a brand new chain.
    function testSelectionOnEmptyTargetCopiesEverything() external {
        DeployMissingTokensHarness harness = new DeployMissingTokensHarness();
        TokenConfig[] memory missing = harness.selectMissing(new TokenInstance[](0));
        assertEq(missing.length, LibTokenInvariants.productionTokensBase().length, "expected the full Base set");
    }

    /// @notice Base is the SOURCE, so dispatching against it is a
    /// wrong-network dispatch rather than a no-op.
    function testTargetTokensRejectsBase() external {
        DeployMissingTokensHarness harness = new DeployMissingTokensHarness();
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedTargetChain.selector, LibSafeInvariants.BASE_CHAIN_ID));
        harness.targetTokens();
    }

    /// @notice An unknown chain is rejected rather than silently resolving to
    /// an empty table, which would otherwise read as "copy everything".
    function testTargetTokensRejectsUnknownChain() external {
        DeployMissingTokensHarness harness = new DeployMissingTokensHarness();
        vm.chainId(123456);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedTargetChain.selector, 123456));
        harness.targetTokens();
    }

    /// @notice Each supported target chain resolves to its own table, keyed
    /// by chain id.
    function testTargetTokensResolvesPerChain() external {
        DeployMissingTokensHarness harness = new DeployMissingTokensHarness();

        vm.chainId(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        TokenInstance[] memory ethereum = harness.targetTokens();
        assertEq(ethereum.length, LibTokenInvariants.productionTokensEthereum().length, "Ethereum table mismatch");

        vm.chainId(LibSafeInvariants.HYPEREVM_CHAIN_ID);
        TokenInstance[] memory hyperevm = harness.targetTokens();
        assertEq(hyperevm.length, LibTokenInvariants.productionTokensHyperEvm().length, "HyperEVM table mismatch");
    }

    /// @notice `run()` reverts `DeployerNotDeployed` when the 0.1.1 core has
    /// not been broadcast to the active chain — the pre-bootstrap state, and
    /// the first guard in the pre-flight chain.
    function testRunRevertsWhenCoreNotDeployed() external {
        vm.expectRevert(
            abi.encodeWithSelector(DeployerNotDeployed.selector, LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1)
        );
        script.run();
    }
}
