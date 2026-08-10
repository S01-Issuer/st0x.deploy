// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    DeployMissingTokens,
    DeployerNotDeployed,
    NoMissingTokens,
    TokenTableMisaligned,
    TokenTableTooShort,
    UnsupportedTargetChain
} from "../../script/20260807-deploy-missing-tokens.s.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {LibProdTokenConfig, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {DeployMissingTokensHarness} from "./DeployMissingTokensHarness.sol";

/// @title DeployMissingTokensTest
/// @notice Coverage for the unified token-copy script. The selection joins
/// two in-code tables (Base vs the target chain), so it is PURE — testable
/// without a fork — and the deploy pre-flight reuses the gate chain the
/// per-chain prod pins already exercise against live state.
contract DeployMissingTokensTest is Test {
    DeployMissingTokens internal script;
    DeployMissingTokensHarness internal harness;

    function setUp() external {
        script = new DeployMissingTokens();
        harness = new DeployMissingTokensHarness();
    }

    /// @notice A chain whose table already carries every Base underlying has
    /// nothing to copy. This is the guard that stops a re-dispatch minting
    /// duplicates of tokens that already landed.
    function testSelectionRevertsWhenTargetMatchesBase() external {
        vm.expectRevert(NoMissingTokens.selector);
        harness.selectMissing(
            LibProdTokenConfig.productionTokenConfigs(),
            LibTokenInvariants.productionTokensBase(),
            LibTokenInvariants.productionTokensBase()
        );
    }

    /// @notice A target chain missing a Base token selects exactly that token,
    /// by `underlying`, and nothing else. Built by dropping one row from a
    /// copy of Base rather than by hardcoding a ticker, so the test does not
    /// go stale as the token set grows.
    function testSelectionPicksTheTokensTheTargetLacks() external view {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        assertGt(base.length, 1, "need at least two Base tokens to drop one");

        uint256 dropped = base.length - 1;
        TokenInstance[] memory target = new TokenInstance[](base.length - 1);
        for (uint256 i = 0; i < dropped; i++) {
            target[i] = base[i];
        }

        TokenConfig[] memory missing = harness.selectMissing(LibProdTokenConfig.productionTokenConfigs(), base, target);
        assertEq(missing.length, 1, "expected exactly the dropped token");
        assertEq(missing[0].underlying, base[dropped].underlying, "selected the wrong token");
    }

    /// @notice An empty target table selects the whole Base set — the
    /// bootstrap case for a brand new chain.
    function testSelectionOnEmptyTargetCopiesEverything() external view {
        TokenConfig[] memory missing = harness.selectMissing(
            LibProdTokenConfig.productionTokenConfigs(),
            LibTokenInvariants.productionTokensBase(),
            new TokenInstance[](0)
        );
        assertEq(missing.length, LibTokenInvariants.productionTokensBase().length, "expected the full Base set");
    }

    /// @notice A config table running AHEAD of Base is a normal state, not a
    /// drift: rows are authored when a ticker is chosen and Base is pinned
    /// when it is deployed, so the config table leads until the Base deploy
    /// lands. The trailing rows Base does not carry are inert — selection
    /// still reads only the Base rows, and only the ones the target lacks.
    function testSelectionToleratesAConfigTableAheadOfBase() external view {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();

        TokenConfig[] memory ahead = new TokenConfig[](configs.length + 2);
        for (uint256 i = 0; i < configs.length; i++) {
            ahead[i] = configs[i];
        }
        ahead[configs.length] = TokenConfig("AAAA", "Ahead Of Base One ST0x", "tAAAA");
        ahead[configs.length + 1] = TokenConfig("BBBB", "Ahead Of Base Two ST0x", "tBBBB");

        TokenConfig[] memory missing = harness.selectMissing(ahead, base, new TokenInstance[](0));
        assertEq(missing.length, base.length, "the un-deployed rows must not be selected");
        assertEq(missing[base.length - 1].underlying, base[base.length - 1].underlying, "selected past the Base table");
    }

    /// @notice A config table SHORTER than Base is the genuine error: a
    /// deployed Base row would have no name/symbol to deploy under.
    function testSelectionRevertsWhenConfigTableIsShorterThanBase() external {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();

        TokenConfig[] memory short = new TokenConfig[](base.length - 1);
        for (uint256 i = 0; i < short.length; i++) {
            short[i] = configs[i];
        }

        vm.expectRevert(abi.encodeWithSelector(TokenTableTooShort.selector, base.length - 1, base.length));
        harness.selectMissing(short, base, new TokenInstance[](0));
    }

    /// @notice Every name/symbol deployed is read from the config row at the
    /// Base row's index, so a row-for-row key mismatch must abort rather than
    /// deploy a token under the wrong underlying's strings. Drifted by
    /// swapping two adjacent config rows, which leaves both tables the same
    /// length — the failure the length check cannot see.
    function testSelectionRevertsWhenConfigRowsDriftFromBase() external {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        assertGt(base.length, 1, "need at least two rows to swap");

        TokenConfig[] memory drifted = new TokenConfig[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            drifted[i] = configs[i];
        }
        (drifted[0], drifted[1]) = (drifted[1], drifted[0]);

        vm.expectRevert(
            abi.encodeWithSelector(TokenTableMisaligned.selector, 0, drifted[0].underlying, base[0].underlying)
        );
        harness.selectMissing(drifted, base, new TokenInstance[](0));
    }

    /// @notice Base is the SOURCE, so dispatching against it is a
    /// wrong-network dispatch rather than a no-op.
    function testTargetTokensRejectsBase() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedTargetChain.selector, LibSafeInvariants.BASE_CHAIN_ID));
        harness.targetTokens();
    }

    /// @notice An unknown chain is rejected rather than silently resolving to
    /// an empty table, which would otherwise read as "copy everything".
    function testTargetTokensRejectsUnknownChain() external {
        vm.chainId(123456);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedTargetChain.selector, 123456));
        harness.targetTokens();
    }

    /// @notice Each supported target chain resolves to its own table, keyed
    /// by chain id.
    function testTargetTokensResolvesPerChain() external {
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
