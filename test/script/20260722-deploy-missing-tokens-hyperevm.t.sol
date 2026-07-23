// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    DeployMissingTokensHyperEvm,
    DeployerNotDeployed
} from "../../script/20260722-deploy-missing-tokens-hyperevm.s.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibProdTokenConfig, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";

/// @title DeployMissingTokensHyperEvmTest
/// @notice Coverage for the HyperEVM token deploy (RAI-1511). Selection is
/// pure over the in-code tables; at authoring time the HyperEVM table is
/// entirely all-zero, so the selection is the WHOLE canonical set — the
/// initial bootstrap as a gap-fill. The post-execution pin PR flips the
/// selection expectation to `NoMissingTokens`, mirroring the Ethereum
/// gap-fill's lifecycle.
contract DeployMissingTokensHyperEvmTest is Test {
    DeployMissingTokensHyperEvm internal script;

    function setUp() external {
        script = new DeployMissingTokensHyperEvm();
    }

    /// @notice Every canonical config row is selected: the HyperEVM table is
    /// all-zero pre-bootstrap, and the selection tracks the canonical set's
    /// size so a token added before the deploy executes is picked up
    /// automatically.
    function testSelectsTheEntireCanonicalSet() external {
        TokenConfig[] memory missing = new DeployMissingTokensHyperEvmHarness().selectMissing();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        assertEq(missing.length, configs.length, "pre-bootstrap selection covers the whole canonical set");
        for (uint256 i = 0; i < missing.length; i++) {
            assertEq(missing[i].underlying, configs[i].underlying, "selection order tracks the canonical set");
        }
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

/// @dev Exposes the internal selection for the pure selection test.
contract DeployMissingTokensHyperEvmHarness is DeployMissingTokensHyperEvm {
    function selectMissing() external pure returns (TokenConfig[] memory) {
        return _selectMissing();
    }
}
