// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin-contracts-5.7.0/interfaces/IERC4626.sol";
import {IReceiptV3} from "rain-vats-0.2.25/src/interface/IReceiptV3.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.25/src/interface/IReceiptVaultV3.sol";

import {IAuthorisable} from "../../../src/interface/IAuthorisable.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../../src/lib/LibBeaconInvariants.sol";
import {LibInvariants} from "../../../src/lib/LibInvariants.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";

/// @title LibTokenInvariantsZerogTest
/// @notice The hydrated 0G token table against live 0G right after the token creation's last bundle.
contract LibTokenInvariantsZerogTest is Test {
    /// @notice The block of Safe nonce 5, the last creation bundle, tx
    /// 0xe6872cd5302397d09aaa0d68b00e04e1f348ec13e720e519900118b555e25862.
    uint256 internal constant ZEROG_LAST_BUNDLE_BLOCK = 51156480;

    function setUp() external {
        vm.createSelectFork(LibStoxDeployNetworks.ZEROG, ZEROG_LAST_BUNDLE_BLOCK);
    }

    /// @notice The multichain production bundle passes on live 0G for 0G's table and 0G's US clone, and every vault
    /// is owned by the 0G timelock.
    function testProductionStateHoldsOnLiveZerog() external view {
        uint256 id = LibSafeInvariants.ZEROG_CHAIN_ID;
        assertEq(block.chainid, id, "0G fork");
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(id);
        LibInvariants.assertProductionState(tokens, LibAuthoriserInvariants.authoriserForChainId(id));
        LibTokenInvariants.assertUniformOwnership(tokens, LibTimelockInvariants.timelockForChainId(id));
    }

    /// @notice Every row's three legs are 0G's token proxies, wired to each other, named from the row's config and
    /// on the row's region authoriser.
    function testEachRowIsALiveZerogToken() external view {
        uint256 id = LibSafeInvariants.ZEROG_CHAIN_ID;
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensZerog();
        TokenConfig[] memory rows = LibProdTokenConfig.canonicalTokenConfigs();
        bytes32[4] memory proxyCodehashes = LibBeaconInvariants.prodTokenProxyCodehashesForChainId(id);
        address us = LibAuthoriserInvariants.authoriserForChainId(id);
        assertEq(tokens.length, rows.length, "one row per config");
        for (uint256 i = 0; i < tokens.length; i++) {
            TokenInstance memory token = tokens[i];
            string memory label = token.underlying;
            assertEq(token.underlying, rows[i].underlying, label);
            assertEq(
                token.receipt.codehash,
                proxyCodehashes[LibBeaconInvariants.RECEIPT_BEACON_INDEX],
                string.concat(label, " receipt proxy")
            );
            assertEq(
                token.receiptVault.codehash,
                proxyCodehashes[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX],
                string.concat(label, " vault proxy")
            );
            assertEq(
                token.wrappedTokenVault.codehash,
                proxyCodehashes[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX],
                string.concat(label, " wrapper proxy")
            );
            assertEq(
                address(IReceiptVaultV3(payable(token.receiptVault)).receipt()),
                token.receipt,
                string.concat(label, " vault receipt")
            );
            assertEq(IReceiptV3(token.receipt).manager(), token.receiptVault, string.concat(label, " receipt manager"));
            assertEq(
                IERC4626(token.wrappedTokenVault).asset(), token.receiptVault, string.concat(label, " wrapper asset")
            );
            assertEq(IERC20Metadata(token.receiptVault).symbol(), rows[i].symbol, string.concat(label, " symbol"));
            assertEq(IERC20Metadata(token.receiptVault).name(), rows[i].name, string.concat(label, " name"));
            assertEq(
                IAuthorisable(token.receiptVault).authorizer(),
                LibTokenInvariants.expectedAuthoriser(token.underlying, us, id),
                string.concat(label, " authoriser")
            );
        }
    }
}
