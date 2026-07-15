// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    DeployTokensEthereum,
    DeployerNotDeployed,
    EthereumSafeNotReady
} from "../../script/20260706-deploy-tokens-ethereum.s.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";

/// @title DeployTokensEthereumTest
/// @notice Inverted pre-flight coverage for the Ethereum token-deploy script.
/// The happy path needs the full V4 core + a live, policy-aligned Ethereum
/// Safe + a hydrated clone pin + a hydrated token table, none of which exist
/// until the bootstrap executes — so the value here is proving each
/// forcing-function fires in order, keeping the script red until its upstream
/// state settles (OPERATIONAL_SCRIPTS.md § forcing-function pattern).
///
/// The first two guards fire before Ethereum carries any state: the V4 core
/// must be deployed, then the Ethereum token-owner Safe — a DISTINCT per-chain
/// address — must be pinned. The later guards (clone pin, token-table
/// hydration, per-vault ownership) sit behind the Safe pin and cannot be
/// tripped until it lands; this suite flips to cover them once it does.
contract DeployTokensEthereumTest is Test {
    DeployTokensEthereum internal script;

    function setUp() external {
        script = new DeployTokensEthereum();
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

    /// `authorizeTokens()` reverts `EthereumSafeNotReady` while the Ethereum
    /// token-owner Safe address is unpinned (`address(0)`). The Safe is a
    /// distinct per-chain address deployed out-of-band; until it is pinned,
    /// there is no Safe to author the setAuthorizer bundle against. This is the
    /// forcing function that blocks the bundle before the Safe exists.
    function testAuthorizeTokensRevertsWhenSafeNotReady() external {
        vm.expectRevert(abi.encodeWithSelector(EthereumSafeNotReady.selector, address(0)));
        script.authorizeTokens();
    }

    /// `verify()` shares the same Safe pre-flight, so it too reverts
    /// `EthereumSafeNotReady` until the Safe address is pinned.
    function testVerifyRevertsWhenSafeNotReady() external {
        vm.expectRevert(abi.encodeWithSelector(EthereumSafeNotReady.selector, address(0)));
        script.verify("out/tokens-ethereum-authorize.json");
    }
}
