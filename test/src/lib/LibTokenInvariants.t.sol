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
import {LibLocalProdState} from "../../lib/LibLocalProdState.sol";

/// @title LibTokenInvariantsTest
/// @notice The token-side uniformity invariants tripped by a mocked
/// `owner()` / `authorizer()` drift on local Base state, and the per-chain
/// token tables.
contract LibTokenInvariantsTest is Test {
    LibTokenInvariantsHarness internal harness;

    function selectLocalBase() internal {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        harness = new LibTokenInvariantsHarness();
    }

    /// @notice tMC is held to the EU authoriser, not the V4 one: wiring it to
    /// the shared authoriser would let every US-fleet depositor mint it, so
    /// that state must trip the invariant.
    function testInvertedEuTokenOnTheSharedAuthoriser() external {
        selectLocalBase();
        LibLocalProdState.tokens(vm, LibSafeInvariants.BASE_CHAIN_ID);
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
        selectLocalBase();
        LibLocalProdState.tokens(vm, LibSafeInvariants.BASE_CHAIN_ID);
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
        selectLocalBase();
        address expectedOwner = LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK;
        address rogueOwner = address(0xBADC0DE);
        address victim = LibTokenInvariants.MSTR_RECEIPT_VAULT;
        vm.mockCall(victim, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(rogueOwner));
        vm.expectRevert(abi.encodeWithSelector(ReceiptVaultOwnerMismatch.selector, victim, expectedOwner, rogueOwner));
        harness.callAssertUniformOwnership(expectedOwner);
    }

    /// How many rows of `table` carry `underlying`.
    function rowsFor(TokenInstance[] memory table, string memory underlying) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < table.length; i++) {
            if (keccak256(bytes(table[i].underlying)) == keccak256(bytes(underlying))) count++;
        }
    }

    /// `table` carries each of Base's underlyings and each of the six off-Base
    /// tokens once, and nothing else. Rows pair by underlying, not by index.
    function assertBaseRowsPlusTheSix(TokenInstance[] memory table, string memory chain) internal pure {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        TokenConfig[] memory six = LibProdTokenConfig.offBaseTokenConfigs();
        assertEq(six.length, 6, "six off-Base tokens");
        assertEq(table.length, base.length + six.length, string.concat(chain, " token table length"));
        for (uint256 i = 0; i < base.length; i++) {
            assertEq(rowsFor(table, base[i].underlying), 1, string.concat(chain, " ", base[i].underlying));
        }
        for (uint256 i = 0; i < six.length; i++) {
            assertEq(rowsFor(base, six[i].underlying), 0, string.concat("Base ", six[i].underlying));
            assertEq(rowsFor(table, six[i].underlying), 1, string.concat(chain, " ", six[i].underlying));
        }
    }

    function testEthereumTokenTableIsBaseRowsPlusTheSix() external pure {
        assertBaseRowsPlusTheSix(LibTokenInvariants.productionTokensEthereum(), "Ethereum");
    }

    function testHyperEvmTokenTableIsBaseRowsPlusTheSix() external pure {
        assertBaseRowsPlusTheSix(LibTokenInvariants.productionTokensHyperEvm(), "HyperEVM");
    }

    function testRobinhoodTokenTableIsBaseRowsPlusTheSix() external pure {
        assertBaseRowsPlusTheSix(LibTokenInvariants.productionTokensRobinhood(), "Robinhood Chain");
    }

    function testBscTokenTableIsBaseRowsPlusTheSix() external pure {
        assertBaseRowsPlusTheSix(LibTokenInvariants.productionTokensBsc(), "BNB Smart Chain");
    }

    /// The 0G token table follows the 0G creation rows row-for-row on the
    /// `underlying` key: 65 rows in Ethereum's creation order.
    function testZerogTokenTableFollowsZerogCreationRows() external pure {
        TokenConfig[] memory rows = LibProdTokenConfig.canonicalTokenConfigs();
        TokenInstance[] memory zerog = LibTokenInvariants.productionTokensZerog();
        assertEq(zerog.length, 65, "0G token table length");
        assertEq(rows.length, zerog.length, "0G token table length diverges from its creation rows");
        for (uint256 i = 0; i < rows.length; i++) {
            assertEq(zerog[i].underlying, rows[i].underlying, "0G token underlying diverges from its creation row");
        }
    }

    /// Each 0G row has the legs of Ethereum's row with the same underlying.
    function testZerogRowsAreEthereumsTokens() external pure {
        TokenInstance[] memory zerog = LibTokenInvariants.productionTokensZerog();
        TokenInstance[] memory ethereum = LibTokenInvariants.productionTokensEthereum();
        for (uint256 i = 0; i < zerog.length; i++) {
            bytes32 key = keccak256(bytes(zerog[i].underlying));
            bool found = false;
            for (uint256 j = 0; j < ethereum.length; j++) {
                if (keccak256(bytes(ethereum[j].underlying)) != key) continue;
                found = true;
                assertEq(zerog[i].receipt, ethereum[j].receipt, string.concat(zerog[i].underlying, " receipt"));
                assertEq(
                    zerog[i].receiptVault,
                    ethereum[j].receiptVault,
                    string.concat(zerog[i].underlying, " receipt vault")
                );
                assertEq(
                    zerog[i].wrappedTokenVault,
                    ethereum[j].wrappedTokenVault,
                    string.concat(zerog[i].underlying, " wrapper")
                );
            }
            assertTrue(found, string.concat(zerog[i].underlying, " on Ethereum"));
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
        assertTokenAddresses(LibTokenInvariants.productionTokensZerog());
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
