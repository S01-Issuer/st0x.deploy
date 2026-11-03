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
import {LibRainDeploy} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {LibLocalProdState} from "../../lib/LibLocalProdState.sol";

/// @title LibTokenInvariantsTest
/// @notice The token-side uniformity invariants tripped by a mocked
/// `owner()` / `authorizer()` drift on a Base fork, and the per-chain token
/// tables.
contract LibTokenInvariantsTest is Test {
    LibTokenInvariantsHarness internal harness;

    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        harness = new LibTokenInvariantsHarness();
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
    /// drift.
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
    /// `underlying` key.
    function testRobinhoodTokenTableMirrorsBaseUnderlyings() external pure {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        TokenInstance[] memory robinhood = LibTokenInvariants.productionTokensRobinhood();
        assertEq(robinhood.length, base.length, "Robinhood Chain token table length diverges from Base");
        for (uint256 i = 0; i < base.length; i++) {
            assertEq(robinhood[i].underlying, base[i].underlying, "Robinhood Chain token underlying diverges from Base");
        }
    }

    /// The BNB Smart Chain token table mirrors Base row-for-row on the
    /// `underlying` key.
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

    /// @notice Base's table with every vault on its region's authoriser
    /// passes the Base overload against the production authoriser.
    function testAssertUniformAuthoriserPassesOnLocalBase() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        LibLocalProdState.tokens(vm, LibSafeInvariants.BASE_CHAIN_ID);
        LibTokenInvariants.assertUniformAuthoriser(LibAuthoriserInvariants.STOX_PROD_AUTHORISER);
    }

    /// @notice On every chain its table with every vault on its region's
    /// authoriser passes the table overload against the chain's US clone.
    function testAssertUniformAuthoriserTablePassesOnEveryChain() external {
        uint256[] memory chainIds = LibLocalProdState.chainIds();
        for (uint256 i = 0; i < chainIds.length; i++) {
            vm.clearMockedCalls();
            vm.chainId(chainIds[i]);
            LibLocalProdState.tokens(vm, chainIds[i]);
            LibTokenInvariants.assertUniformAuthoriser(
                LibTokenInvariants.productionTokensForChainId(chainIds[i]),
                LibAuthoriserInvariants.authoriserForChainId(chainIds[i])
            );
        }
    }
}
