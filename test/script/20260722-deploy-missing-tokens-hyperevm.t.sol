// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    DeployMissingTokensHyperEvm,
    DeployerNotDeployed,
    NoMissingTokens
} from "../../script/20260722-deploy-missing-tokens-hyperevm.s.sol";
import {DeployMissingTokensHyperEvmHarness} from "./DeployMissingTokensHyperEvmHarness.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";

/// @title DeployMissingTokensHyperEvmTest
/// @notice Coverage for the HyperEVM token deploy (RAI-1511). The script is
/// self-scoping over the in-code tables (canonical config vs the HyperEVM
/// token table), so the selection logic is PURE — testable without a fork —
/// and the deploy pre-flight reuses the gate chain the per-chain prod pins
/// already exercise against live HyperEVM.
contract DeployMissingTokensHyperEvmTest is Test {
    DeployMissingTokensHyperEvm internal script;

    function setUp() external {
        script = new DeployMissingTokensHyperEvm();
    }

    /// @notice The HyperEVM table is fully hydrated (the bootstrap deploy
    /// EXECUTED 2026-07-24 and every row is pinned), so the selection refuses
    /// to author anything: `NoMissingTokens`. This is the guard that keeps a
    /// re-dispatch of the EXECUTED script from minting duplicates. When a
    /// future token lands in the canonical config with an all-zero HyperEVM
    /// row, this flips back to a positive selection expectation.
    function testSelectionRevertsWhenTableFullyHydrated() external {
        DeployMissingTokensHyperEvmHarness harness = new DeployMissingTokensHyperEvmHarness();
        vm.expectRevert(NoMissingTokens.selector);
        harness.selectMissing();
    }

    /// @notice `run()` reverts `DeployerNotDeployed` when the 0.1.1 core has
    /// not been broadcast to the active chain — the pre-bootstrap HyperEVM
    /// state, and the first guard in the pre-flight chain.
    function testRunRevertsWhenCoreNotDeployed() external {
        vm.expectRevert(
            abi.encodeWithSelector(DeployerNotDeployed.selector, LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1)
        );
        script.run();
    }
}
