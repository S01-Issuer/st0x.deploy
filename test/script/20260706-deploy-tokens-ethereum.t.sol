// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    DeployTokensEthereum,
    DeployerNotDeployed,
    EthereumCloneNotReady
} from "../../script/20260706-deploy-tokens-ethereum.s.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibProdAuthoriserClones} from "../../src/lib/LibProdAuthoriserClones.sol";
import {LibSafeInvariants, SafeProxyCodehashMismatch} from "../../src/lib/LibSafeInvariants.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title DeployTokensEthereumTest
/// @notice Inverted pre-flight coverage for the Ethereum token-deploy
/// script. The happy path needs the full V4 core + a live, policy-aligned
/// Ethereum Safe + a hydrated clone pin + a hydrated token table, none of
/// which exist until the bootstrap executes — so the value here is proving
/// each forcing-function fires in order, keeping the script red until its
/// upstream state settles (OPERATIONAL_SCRIPTS.md § forcing-function
/// pattern). The later guards (token-table hydration, per-vault ownership)
/// cannot be tripped until the clone + tokens are pinned; this suite flips
/// to cover them once those pins land.
contract DeployTokensEthereumTest is Test {
    DeployTokensEthereum internal script;

    function setUp() external {
        script = new DeployTokensEthereum();
        // Persist across `createSelectFork` so the Base-fork tests can still
        // call into the script (a fork switch otherwise leaves its address
        // code-less on the new fork state).
        vm.makePersistent(address(script));
    }

    /// `run()` reverts `DeployerNotDeployed` when the V4 core has not been
    /// broadcast to the active chain — the unified deployer's pinned address
    /// has no code, so no token can be deployed. (No fork: the deployer is
    /// absent, which is the pre-bootstrap Ethereum state.)
    function testRunRevertsWhenCoreNotDeployed() external {
        vm.expectRevert(
            abi.encodeWithSelector(DeployerNotDeployed.selector, LibProdDeployCurrent.STOX_UNIFIED_DEPLOYER)
        );
        script.run();
    }

    /// `authorizeTokens()` reverts through the Safe invariant when the
    /// Ethereum Safe is not live: with no fork the matched Safe address has
    /// no code, so the pinned-proxy-codehash check trips first. This is the
    /// forcing function that blocks authoring the bundle before the Safe is
    /// deployed + policy-aligned to Base.
    function testAuthorizeTokensRevertsWhenSafeNotLive() external {
        vm.expectPartialRevert(SafeProxyCodehashMismatch.selector);
        script.authorizeTokens();
    }

    /// On a Base fork the "Ethereum" Safe IS present — it is the SAME
    /// address as the Base token-owner Safe (matched-address Safe) and it is
    /// live + policy-aligned — so the Safe invariant passes and the NEXT
    /// forcing function trips: the Ethereum authoriser clone pin is still the
    /// `address(0)` placeholder. This directly exercises the matched-address
    /// property AND the clone forcing function in one path.
    function testAuthorizeTokensRevertsWhenClonePlaceholderOnBaseFork() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        // Precondition the test relies on: the Ethereum clone pin is still a
        // placeholder (flips this test to the next guard once hydrated).
        require(
            LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM == address(0),
            "Ethereum clone pin hydrated - advance this test to the token-table guard"
        );
        vm.expectRevert(abi.encodeWithSelector(EthereumCloneNotReady.selector, address(0)));
        script.authorizeTokens();
    }

    /// `verify()` shares the same pre-flight ordering, so on a Base fork it
    /// too clears the Safe invariant and trips on the placeholder clone pin.
    function testVerifyRevertsWhenClonePlaceholderOnBaseFork() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        require(
            LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM == address(0),
            "Ethereum clone pin hydrated - advance this test"
        );
        vm.expectRevert(abi.encodeWithSelector(EthereumCloneNotReady.selector, address(0)));
        script.verify("out/tokens-ethereum-authorize.json");
    }
}
