// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";

import {IAuthorisable} from "../../src/interface/IAuthorisable.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {CreateZerogTokensHarness} from "./CreateZerogTokensHarness.sol";

/// @title CreateZerogTokensRowsAreLiveTokensTest
/// @notice On live Ethereum and HyperEVM, the vault the 0.1.1 receipt-vault beacon-set deployer created at 0G row
/// `i`'s nonce carries that row's name and symbol and sits on the authoriser clone the script picks for the row's
/// region on that chain.
contract CreateZerogTokensRowsAreLiveTokensTest is Test {
    uint256 internal constant ETHEREUM_BLOCK = 26465320;
    uint256 internal constant HYPEREVM_BLOCK = 51879801;

    function assertRowsAreLiveTokens(string memory network, uint256 blockNumber) internal {
        vm.createSelectFork(network, blockNumber);
        CreateZerogTokensHarness script = new CreateZerogTokensHarness(network);
        uint256 chainId = block.chainid;
        vm.chainId(LibSafeInvariants.ZEROG_CHAIN_ID);
        TokenConfig[] memory rows = script.callConfigs();
        vm.chainId(chainId);
        assertGt(rows.length, 0, "0G rows");
        assertNotEq(
            LibAuthoriserInvariants.euAuthoriserForChainId(chainId),
            LibAuthoriserInvariants.authoriserForChainId(chainId),
            "US and EU clones differ"
        );
        for (uint256 i = 0; i < rows.length; i++) {
            TokenInstance memory live = script.callRowToken(rows[i], i);
            string memory label = string.concat(network, " ", rows[i].underlying);
            assertEq(IERC20Metadata(live.receiptVault).name(), rows[i].name, string.concat(label, " name"));
            assertEq(IERC20Metadata(live.receiptVault).symbol(), rows[i].symbol, string.concat(label, " symbol"));
            assertEq(
                IAuthorisable(live.receiptVault).authorizer(),
                script.callAuthoriserFor(rows[i]),
                string.concat(label, " authoriser")
            );
        }
    }

    function testEachRowIsEthereumsLiveTokenAtItsNonce() external {
        assertRowsAreLiveTokens(LibRainDeploy.ETHEREUM, ETHEREUM_BLOCK);
    }

    function testEachRowIsHyperEvmsLiveTokenAtItsNonce() external {
        assertRowsAreLiveTokens(LibRainDeploy.HYPEREVM, HYPEREVM_BLOCK);
    }
}
