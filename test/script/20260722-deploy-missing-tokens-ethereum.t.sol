// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    DeployMissingTokensEthereum,
    DeployerNotDeployed,
    NoMissingTokens
} from "../../script/20260722-deploy-missing-tokens-ethereum.s.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";

/// @title DeployMissingTokensEthereumTest
/// @notice Coverage for the gap-filling Ethereum token deploy. The script is
/// self-scoping over the in-code tables (canonical config vs the Ethereum
/// token table), so the selection logic is PURE — testable without a fork —
/// and the deploy pre-flight reuses the gate chain the 20260706 suite and
/// the per-chain prod pins already exercise against live Ethereum.
contract DeployMissingTokensEthereumTest is Test {
    DeployMissingTokensEthereum internal script;

    function setUp() external {
        script = new DeployMissingTokensEthereum();
    }

    /// @notice The selection is exactly the all-zero Ethereum table rows —
    /// RKLB at the time of authoring. When the deploy executes and the row
    /// is hydrated, the selection empties, `run()` flips to
    /// `NoMissingTokens`, and the post-execution pin PR retires/updates
    /// this expectation.
    function testSelectsExactlyTheMissingTokens() external {
        TokenConfig[] memory missing = new DeployMissingTokensEthereumHarness().selectMissing();
        assertEq(missing.length, 1, "expected exactly one missing token (RKLB)");
        assertEq(missing[0].underlying, "RKLB", "missing token is RKLB");
        assertEq(missing[0].name, "Rocket Lab USA Inc ST0x", "RKLB canonical name");
        assertEq(missing[0].symbol, "tRKLB", "RKLB canonical symbol");
    }

    /// @notice `run()` reverts `DeployerNotDeployed` when the 0.1.1 core has
    /// not been broadcast to the active chain (no fork: the pre-bootstrap
    /// state, and the first guard in the pre-flight chain).
    function testRunRevertsWhenCoreNotDeployed() external {
        vm.expectRevert(
            abi.encodeWithSelector(DeployerNotDeployed.selector, LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1)
        );
        script.run();
    }
}

/// @dev Exposes the internal selection for the pure selection test.
contract DeployMissingTokensEthereumHarness is DeployMissingTokensEthereum {
    function selectMissing() external pure returns (TokenConfig[] memory) {
        return _selectMissing();
    }
}
