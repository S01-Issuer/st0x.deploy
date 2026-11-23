// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin-contracts-5.7.0/interfaces/IERC4626.sol";
import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.25/src/interface/IReceiptVaultV3.sol";

import {IAuthorisable} from "../../../src/interface/IAuthorisable.sol";
import {IOwnable} from "../../../src/interface/IOwnable.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";

/// @title LibTokenInvariantsOffBaseRowsTest
/// @notice On each chain whose table carries the six off-Base tokens, each of those rows is the live token: its
/// vault's name and symbol, its vault on the chain's US authoriser clone and owned by the chain's timelock, its
/// receipt the vault's, and its wrapper over the vault.
contract LibTokenInvariantsOffBaseRowsTest is Test {
    uint256 internal constant ETHEREUM_BLOCK = 26465599;
    uint256 internal constant HYPEREVM_BLOCK = 51883233;
    uint256 internal constant ROBINHOOD_BLOCK = 120107398;
    uint256 internal constant BSC_BLOCK = 134944151;

    function assertRowIsLive(TokenInstance memory row, TokenConfig memory config, address us, address timelock)
        internal
        view
    {
        string memory label = string.concat(vm.toString(block.chainid), " ", config.underlying);
        assertEq(IERC20Metadata(row.receiptVault).name(), config.name, string.concat(label, " name"));
        assertEq(IERC20Metadata(row.receiptVault).symbol(), config.symbol, string.concat(label, " symbol"));
        assertEq(IAuthorisable(row.receiptVault).authorizer(), us, string.concat(label, " authoriser"));
        assertEq(IOwnable(row.receiptVault).owner(), timelock, string.concat(label, " owner"));
        assertEq(
            address(IReceiptVaultV3(payable(row.receiptVault)).receipt()), row.receipt, string.concat(label, " receipt")
        );
        assertEq(IERC4626(row.wrappedTokenVault).asset(), row.receiptVault, string.concat(label, " wrapper asset"));
    }

    function assertSixRowsAreLive(string memory network, uint256 blockNumber) internal {
        vm.createSelectFork(network, blockNumber);
        uint256 chainId = block.chainid;
        address us = LibAuthoriserInvariants.authoriserForChainId(chainId);
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        assertNotEq(us, LibAuthoriserInvariants.euAuthoriserForChainId(chainId), "US and EU clones differ");
        TokenInstance[] memory table = LibTokenInvariants.productionTokensForChainId(chainId);
        TokenConfig[] memory six = LibProdTokenConfig.offBaseTokenConfigs();
        assertEq(six.length, 6, "six off-Base tokens");
        for (uint256 k = 0; k < six.length; k++) {
            uint256 found = 0;
            for (uint256 i = 0; i < table.length; i++) {
                if (keccak256(bytes(table[i].underlying)) != keccak256(bytes(six[k].underlying))) continue;
                found++;
                assertRowIsLive(table[i], six[k], us, timelock);
            }
            assertEq(found, 1, string.concat(network, " ", six[k].underlying, " rows"));
        }
    }

    function testEthereumSixRowsAreTheLiveTokens() external {
        assertSixRowsAreLive(LibRainDeploy.ETHEREUM, ETHEREUM_BLOCK);
    }

    function testHyperEvmSixRowsAreTheLiveTokens() external {
        assertSixRowsAreLive(LibRainDeploy.HYPEREVM, HYPEREVM_BLOCK);
    }

    function testRobinhoodSixRowsAreTheLiveTokens() external {
        assertSixRowsAreLive(LibRainDeploy.ROBINHOOD, ROBINHOOD_BLOCK);
    }

    function testBscSixRowsAreTheLiveTokens() external {
        assertSixRowsAreLive(LibRainDeploy.BSC, BSC_BLOCK);
    }
}
