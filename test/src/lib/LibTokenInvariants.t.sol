// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {
    LibTokenInvariants,
    TokenInstance,
    IOwnable,
    ReceiptVaultOwnerMismatch,
    ReceiptVaultAuthoriserMismatch
} from "../../../src/lib/LibTokenInvariants.sol";
import {IAuthorisable} from "../../../src/interface/IAuthorisable.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariantsHarness} from "./LibTokenInvariantsHarness.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";

/// @title LibTokenInvariantsTest
/// @notice Fork tests for the token-side uniformity invariants: every
/// production receipt vault on Base shares the same `owner()` and the same
/// `authorizer()`.
///
/// Both uniformity invariants currently hold on-chain (every vault is
/// owned by `LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK` and reports the V4
/// authoriser clone `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE`), so the
/// positive cases pass against the live Base fork. The inverted
/// ownership-drift case is also exercised here for full error-path coverage.
/// @dev Uses an unpinned Base head fork (same precedent as the other
/// prod-state drift detectors in this repo), so the next CI run reflects the
/// current on-chain wiring. Pinning would freeze the invariant assertions
/// against a stale snapshot and let new drift slip through unnoticed.
contract LibTokenInvariantsTest is Test {
    /// @notice External-call harness deployed fresh per test against the
    /// active fork.
    LibTokenInvariantsHarness internal harness;

    /// @notice Selects the Base fork at chain head — deliberately unpinned.
    /// Live drift detector; see contract-level rationale.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        harness = new LibTokenInvariantsHarness();
    }

    /// @notice Every production receipt vault reports
    /// `LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK` as its `owner()`. Passes against
    /// the live chain state: vault ownership is uniform.
    function testProdReceiptVaultsUniformOwnership() external {
        selectBaseFork();
        LibTokenInvariants.assertUniformOwnership(LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
    }

    /// @notice Every production receipt vault reports the V4 authoriser clone
    /// (`LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE`) — the production
    /// authoriser since the V4 swap batch executed on Base (2026-07).
    /// Passes against the live chain state: vault authoriser is uniform.
    /// Deliberately STRICT (not migration-window gated): when a newly
    /// deployed token enters the table still wired to a previous authoriser,
    /// this goes red until its swap batch executes — the forcing function
    /// that keeps the table and the live wiring in lock-step.
    function testProdReceiptVaultsShareUniformAuthoriser() external {
        selectBaseFork();
        LibTokenInvariants.assertUniformAuthoriser(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE);
    }

    /// @notice tMC is held to the EU authoriser, not the V4 one: wiring it to
    /// the shared authoriser would let every US-fleet depositor mint it, so
    /// that state must trip the invariant.
    function testInvertedEuTokenOnTheSharedAuthoriser() external {
        selectBaseFork();
        address v4 = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        address victim = LibTokenInvariants.MC_RECEIPT_VAULT;
        vm.mockCall(victim, abi.encodeWithSelector(IAuthorisable.authorizer.selector), abi.encode(v4));
        vm.expectRevert(
            abi.encodeWithSelector(
                ReceiptVaultAuthoriserMismatch.selector, victim, LibAuthoriserInvariants.STOX_EU_AUTHORISER_CLONE, v4
            )
        );
        harness.callAssertUniformAuthoriser(v4);
    }

    /// @notice And the converse: a US token on the EU authoriser trips it.
    function testInvertedUsTokenOnTheEuAuthoriser() external {
        selectBaseFork();
        address v4 = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        address eu = LibAuthoriserInvariants.STOX_EU_AUTHORISER_CLONE;
        address victim = LibTokenInvariants.WMT_RECEIPT_VAULT;
        vm.mockCall(victim, abi.encodeWithSelector(IAuthorisable.authorizer.selector), abi.encode(eu));
        vm.expectRevert(abi.encodeWithSelector(ReceiptVaultAuthoriserMismatch.selector, victim, v4, eu));
        harness.callAssertUniformAuthoriser(v4);
    }

    /// @notice Token-side ownership drift trips `ReceiptVaultOwnerMismatch`.
    /// Simulated by mocking a single vault's `owner()` to a rogue address;
    /// the assertion reverts surfacing the offending vault. The victim vault
    /// address comes from `LibTokenInvariants` (the source of truth for
    /// production receipt vaults).
    function testInvertedUniformOwnershipDrift() external {
        selectBaseFork();
        address expectedOwner = LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK;
        address rogueOwner = address(0xBADC0DE);
        address victim = LibTokenInvariants.MSTR_RECEIPT_VAULT;
        vm.mockCall(victim, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(rogueOwner));
        vm.expectRevert(abi.encodeWithSelector(ReceiptVaultOwnerMismatch.selector, victim, expectedOwner, rogueOwner));
        harness.callAssertUniformOwnership(expectedOwner);
    }

    /// The Ethereum token table mirrors Base row-for-row on the `underlying`
    /// key — same length, same order — so the two per-chain tables cannot
    /// drift now that the Ethereum table is written out explicitly rather than
    /// derived from Base. (The addresses are still per-chain placeholders,
    /// hydrated by the token pin PR; this guards only the shared shape.)
    function testEthereumTokenTableMirrorsBaseUnderlyings() external pure {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        TokenInstance[] memory eth = LibTokenInvariants.productionTokensEthereum();
        assertEq(eth.length, base.length, "Ethereum token table length diverges from Base");
        for (uint256 i = 0; i < base.length; i++) {
            assertEq(eth[i].underlying, base[i].underlying, "Ethereum token underlying diverges from Base");
        }
    }

    /// The HyperEVM token table mirrors Base row-for-row on the `underlying`
    /// key, for the same reason as Ethereum's.
    function testHyperEvmTokenTableMirrorsBaseUnderlyings() external pure {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        TokenInstance[] memory hyper = LibTokenInvariants.productionTokensHyperEvm();
        assertEq(hyper.length, base.length, "HyperEVM token table length diverges from Base");
        for (uint256 i = 0; i < base.length; i++) {
            assertEq(hyper[i].underlying, base[i].underlying, "HyperEVM token underlying diverges from Base");
        }
    }

    /// The Robinhood Chain token table mirrors Base row-for-row on the
    /// `underlying` key. Its addresses are placeholders until the token
    /// deploy executes there; this guards only the shared shape.
    function testRobinhoodTokenTableMirrorsBaseUnderlyings() external pure {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        TokenInstance[] memory robinhood = LibTokenInvariants.productionTokensRobinhood();
        assertEq(robinhood.length, base.length, "Robinhood Chain token table length diverges from Base");
        for (uint256 i = 0; i < base.length; i++) {
            assertEq(robinhood[i].underlying, base[i].underlying, "Robinhood Chain token underlying diverges from Base");
        }
    }

    /// The BNB Smart Chain token table mirrors Base row-for-row on the
    /// `underlying` key; addresses are placeholders until its token deploy.
    function testBscTokenTableMirrorsBaseUnderlyings() external pure {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        TokenInstance[] memory bsc = LibTokenInvariants.productionTokensBsc();
        assertEq(bsc.length, base.length, "BNB Smart Chain token table length diverges from Base");
        for (uint256 i = 0; i < base.length; i++) {
            assertEq(bsc[i].underlying, base[i].underlying, "BNB Smart Chain token underlying diverges from Base");
        }
    }

    function testDiscardedEuBatchIsNotListed() external pure {
        string[6] memory discarded = ["AIR.PA", "BMW.DE", "MC.PA", "SIE.DE", "MBG.DE", "RHM.DE"];
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 d = 0; d < discarded.length; d++) {
            bytes32 key = keccak256(bytes(discarded[d]));
            for (uint256 i = 0; i < base.length; i++) {
                assertTrue(keccak256(bytes(base[i].underlying)) != key, discarded[d]);
            }
            for (uint256 i = 0; i < configs.length; i++) {
                assertTrue(keccak256(bytes(configs[i].underlying)) != key, discarded[d]);
            }
        }
    }

    function assertTokenAddresses(TokenInstance[] memory tokens) internal pure {
        address[] memory addresses = new address[](tokens.length * 3);
        for (uint256 tokenIndex = 0; tokenIndex < tokens.length; tokenIndex++) {
            addresses[tokenIndex * 3] = tokens[tokenIndex].receipt;
            addresses[tokenIndex * 3 + 1] = tokens[tokenIndex].receiptVault;
            addresses[tokenIndex * 3 + 2] = tokens[tokenIndex].wrappedTokenVault;
        }
        for (uint256 addressIndex = 0; addressIndex < addresses.length; addressIndex++) {
            assertNotEq(addresses[addressIndex], address(0), "production token address is zero");
            for (uint256 previousIndex = 0; previousIndex < addressIndex; previousIndex++) {
                assertNotEq(
                    addresses[addressIndex],
                    addresses[previousIndex],
                    "production token address is duplicated within its chain"
                );
            }
        }
    }

    /// Every receipt, receipt vault and wrapper is nonzero and appears once
    /// per chain, so an aliased or missing leg fails without a fork.
    function testProductionTokenAddressesAreNonzeroAndUniquePerChain() external pure {
        assertTokenAddresses(LibTokenInvariants.productionTokensBase());
        assertTokenAddresses(LibTokenInvariants.productionTokensEthereum());
        assertTokenAddresses(LibTokenInvariants.productionTokensHyperEvm());
        assertTokenAddresses(LibTokenInvariants.productionTokensRobinhood());
        assertTokenAddresses(LibTokenInvariants.productionTokensBsc());
    }

    function assertTokenRow(
        TokenInstance memory token,
        string memory underlying,
        address receipt,
        address receiptVault,
        address wrappedTokenVault
    ) internal pure {
        assertEq(token.underlying, underlying, "underlying");
        assertEq(token.receipt, receipt, "receipt");
        assertEq(token.receiptVault, receiptVault, "receipt vault");
        assertEq(token.wrappedTokenVault, wrappedTokenVault, "wrapped token vault");
    }

    /// The tMC and tDIS rows hold the addresses the Base deploy and the
    /// `20260807-deploy-missing-tokens` copies logged.
    function testMcAndDisRowsMatchDeployments() external pure {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        assertTokenRow(
            base[54],
            "MC",
            0xC3fD55A007CB7e4549A4b5064691c75609b1411b,
            0x6eC2421d74F2AF61b7EE7bCCAE25A3b6a7961Aa0,
            0x378a04202D25659763A02dA5FE77c0a35e64Ce1D
        );
        assertTokenRow(
            base[55],
            "DIS",
            0xc53b863791d8E1de96CA547CF8F3C740e770FAE1,
            0x40584fBad768FF46f299Cf50cAe5b3D437E213Fa,
            0x8EA3c97D23872eC4FAe1cA3189039056b77bc703
        );

        // Ethereum, HyperEVM and Robinhood Chain share the deterministic
        // deployer, so their copies landed at the same addresses.
        TokenInstance[][3] memory sameAddressChains = [
            LibTokenInvariants.productionTokensEthereum(),
            LibTokenInvariants.productionTokensHyperEvm(),
            LibTokenInvariants.productionTokensRobinhood()
        ];
        for (uint256 i = 0; i < sameAddressChains.length; i++) {
            assertTokenRow(
                sameAddressChains[i][54],
                "MC",
                0x9835e52FAFA9A92678C8A9420034706B1edD431e,
                0x4d4D633bf04ABF6e4cF152C7c5c1ecD906Ab3de4,
                0x5Ce8b84756dDdE011734F04dC4bA2930C981B443
            );
            assertTokenRow(
                sameAddressChains[i][55],
                "DIS",
                0x29e7fe750DFffd4D7C8e907C126324B8a5A9AdB7,
                0xd78025Aa344E549A1D76eCE1591c481cC7Bc3548,
                0x81f40cbCFAE7A1aD1f4474eD95A210DfA3B90B0f
            );
        }

        TokenInstance[] memory bsc = LibTokenInvariants.productionTokensBsc();
        assertTokenRow(
            bsc[54],
            "MC",
            0xcf829819FDD164A8B6566d404E67bdFd92F169c2,
            0x28019de1dE36d5fA0077Dfe7859ED54664982081,
            0x69e93548C38132B8bcfA41BbA521Ae5A87c568B4
        );
        assertTokenRow(
            bsc[55],
            "DIS",
            0x67d8ACfE2DADa892411b4A86CBAC6901383C8F4e,
            0xe39a028cdC8a50e655A5b31ba8A48ce36f3A8243,
            0x24eD179E95F643ff9f8235850778160cFA4aeDb7
        );
    }
}
