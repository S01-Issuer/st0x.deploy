// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {DeployTokensEthereum, DeployerNotDeployed} from "../../script/20260706-deploy-tokens-ethereum.s.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";

/// @title DeployTokensEthereumTest
/// @notice Inverted pre-flight coverage for the Ethereum token-deploy script.
/// The happy path needs the full V4 core + a live, policy-aligned Ethereum
/// Safe + a hydrated clone pin, none of which exist until the bootstrap
/// executes — so the value here is proving the first forcing function fires,
/// keeping the script red until its upstream state settles
/// (OPERATIONAL_SCRIPTS.md § forcing-function pattern). `run()` is now a single
/// deploy-key broadcast (deploy → setAuthorizer → transferOwnership to the
/// Safe), so there is one entrypoint and one pre-flight chain: core deployers,
/// then the clone (setAuthorizer target), then the Safe (handoff target).
contract DeployTokensEthereumTest is Test {
    DeployTokensEthereum internal script;

    function setUp() external {
        script = new DeployTokensEthereum();
    }

    /// `run()` reverts `DeployerNotDeployed` when the V4 core has not been
    /// broadcast to the active chain — the unified deployer's pinned address
    /// has no code, so no token can be deployed. (No fork: the deployer is
    /// absent, which is the pre-bootstrap Ethereum state, and is the first
    /// guard in the pre-flight chain.)
    function testRunRevertsWhenCoreNotDeployed() external {
        vm.expectRevert(
            abi.encodeWithSelector(DeployerNotDeployed.selector, LibProdDeployCurrent.STOX_UNIFIED_DEPLOYER)
        );
        script.run();
    }
}
