// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.21/src/lib/LibRainDeploy.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTokenInvariants, NoTokenTableForChain, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";
import {LibTokenInvariantsPerChainHarness} from "./LibTokenInvariantsPerChainHarness.sol";

contract LibTokenInvariantsPerChainTest is Test {
    LibTokenInvariantsPerChainHarness internal lib = new LibTokenInvariantsPerChainHarness();

    function testEachDeploymentChainSelectsItsOwnTable() external pure {
        assertSame(
            LibTokenInvariants.productionTokensForChainId(LibSafeInvariants.BASE_CHAIN_ID),
            LibTokenInvariants.productionTokensBase()
        );
        assertSame(
            LibTokenInvariants.productionTokensForChainId(LibSafeInvariants.ETHEREUM_CHAIN_ID),
            LibTokenInvariants.productionTokensEthereum()
        );
        assertSame(
            LibTokenInvariants.productionTokensForChainId(LibSafeInvariants.HYPEREVM_CHAIN_ID),
            LibTokenInvariants.productionTokensHyperEvm()
        );
        assertSame(
            LibTokenInvariants.productionTokensForChainId(LibSafeInvariants.ROBINHOOD_CHAIN_ID),
            LibTokenInvariants.productionTokensRobinhood()
        );
        assertSame(
            LibTokenInvariants.productionTokensForChainId(LibSafeInvariants.BSC_CHAIN_ID),
            LibTokenInvariants.productionTokensBsc()
        );
    }

    function testBaseTableDiffersFromEveryOtherChainsSoTheSelectionIsObservable() external pure {
        SupportedNetwork[] memory nets =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        for (uint256 i = 0; i < nets.length; i++) {
            if (nets[i].chainId == LibSafeInvariants.BASE_CHAIN_ID) continue;
            TokenInstance[] memory other = LibTokenInvariants.productionTokensForChainId(nets[i].chainId);
            assertTrue(other.length != base.length || other[0].receiptVault != base[0].receiptVault);
        }
    }

    function testReceiptVaultsAreTheTablesReceiptVaultsInOrder() external pure {
        SupportedNetwork[] memory nets =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 i = 0; i < nets.length; i++) {
            TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(nets[i].chainId);
            address[] memory vaults = LibTokenInvariants.productionReceiptVaultsForChainId(nets[i].chainId);
            assertEq(vaults.length, tokens.length);
            for (uint256 j = 0; j < tokens.length; j++) {
                assertEq(vaults[j], tokens[j].receiptVault);
            }
        }
        assertEq(
            LibTokenInvariants.productionReceiptVaults(),
            LibTokenInvariants.productionReceiptVaultsForChainId(LibSafeInvariants.BASE_CHAIN_ID)
        );
    }

    function testUndeployedChainHasNoTable(uint256 chainId) external {
        SupportedNetwork[] memory nets =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 i = 0; i < nets.length; i++) {
            vm.assume(chainId != nets[i].chainId);
        }
        vm.expectRevert(abi.encodeWithSelector(NoTokenTableForChain.selector, chainId));
        lib.productionTokensForChainId(chainId);
    }

    function assertSame(TokenInstance[] memory a, TokenInstance[] memory b) internal pure {
        assertEq(a.length, b.length);
        for (uint256 i = 0; i < a.length; i++) {
            assertEq(a[i].receiptVault, b[i].receiptVault);
        }
    }
}
