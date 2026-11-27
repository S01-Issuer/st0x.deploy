// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {CreateZerogTokensHarness} from "./CreateZerogTokensHarness.sol";

/// @notice One of Ethereum's token slots as its 0.1.1 beacon-set deployers created it.
struct EthereumSlot {
    string underlying;
    address vault;
    address wrapper;
    string symbol;
    string name;
    address authoriser;
}

/// @title CreateZerogTokensEthereumOrderTest
/// @notice Row `i` of the 0G token creation lands at the address Ethereum's deployers gave their `i`th token, so it
/// must be that token: no address names one underlying on 0G and another anywhere else.
contract CreateZerogTokensEthereumOrderTest is Test {
    /// @notice Ethereum's slots that no Base row carries.
    uint256 internal constant FIRST_OFF_BASE_SLOT = 42;

    CreateZerogTokensHarness internal sScript;

    function setUp() external {
        vm.chainId(LibSafeInvariants.ZEROG_CHAIN_ID);
        sScript = new CreateZerogTokensHarness("ethereum-order");
    }

    /// @notice Ethereum slots 42-47 as read on chain from Ethereum's 0.1.1 beacon-set deployers.
    function offBaseSlots() internal pure returns (EthereumSlot[6] memory) {
        address us = address(0x66566cc91dEAf818859bD4b09B7903ac48998157);
        return [
            EthereumSlot(
                "AIR.PA",
                address(0x4Da175A70020EeEFa71C36d710307ed0803Aed60),
                address(0xc3bc6EEf91FfAeBACB13f4c48aC0515C820d2b0c),
                "tAIR.PA",
                "Airbus SE ST0x",
                us
            ),
            EthereumSlot(
                "BMW.DE",
                address(0x6872cEe8E1a07Dd8C1154755f7e215F2973caE52),
                address(0x36FE4dc30b3b4906c9A64D5C957D49388E8d38E8),
                "tBMW.DE",
                "Bayerische Motoren Werke Aktiengesellschaft ST0x",
                us
            ),
            EthereumSlot(
                "MC.PA",
                address(0xaE7115d434c84F2f4a1196BaD67415d479804af1),
                address(0xeaA6da57f120D5a0acB9Ff4807F7990EfBbE303a),
                "tMC.PA",
                unicode"LVMH Moët Hennessy Louis Vuitton SE ST0x",
                us
            ),
            EthereumSlot(
                "SIE.DE",
                address(0x269CA594b6463F0D94086fb2D77dFaad32d1c6C4),
                address(0x08A85a5AcE300e881e7c8828412A3Bdfd6F99054),
                "tSIE.DE",
                "Siemens Aktiengesellschaft ST0x",
                us
            ),
            EthereumSlot(
                "MBG.DE",
                address(0xA1768baE756058fE00dD281C405DDe1C48B00F3B),
                address(0x6a73364EaE305199B62585C4486C24f3b72b2C72),
                "tMBG.DE",
                "Mercedes-Benz Group AG ST0x",
                us
            ),
            EthereumSlot(
                "RHM.DE",
                address(0x8790337c4Ce51b66CBa179129d830A3683780ff6),
                address(0x24ae429A29882b06898afCBAef20BfDb93f67e20),
                "tRHM.DE",
                "Rheinmetall AG ST0x",
                us
            )
        ];
    }

    function zerogTokens() internal view returns (TokenInstance[] memory tokens) {
        tokens = new TokenInstance[](LibProdTokenConfig.canonicalTokenConfigs().length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = sScript.callToken(i);
        }
    }

    function legs(TokenInstance memory token) internal pure returns (address[3] memory) {
        return [token.receipt, token.receiptVault, token.wrappedTokenVault];
    }

    /// @notice Every 0G row gets Ethereum's vault and wrapper for its underlying, and Ethereum's table carries no
    /// underlying the 0G rows do not.
    function testEachRowIsEthereumsTokenForItsUnderlying() external view {
        TokenConfig[] memory rows = LibProdTokenConfig.canonicalTokenConfigs();
        TokenInstance[] memory ethereum = LibTokenInvariants.productionTokensEthereum();
        assertEq(rows.length, 65, "0G rows");
        assertEq(ethereum.length, rows.length, "Ethereum rows");
        for (uint256 i = 0; i < rows.length; i++) {
            TokenInstance memory created = sScript.callToken(i);
            assertEq(created.underlying, rows[i].underlying, "token row underlying");
            bool found = false;
            for (uint256 j = 0; j < ethereum.length; j++) {
                if (keccak256(bytes(ethereum[j].underlying)) != keccak256(bytes(rows[i].underlying))) continue;
                assertFalse(found, string.concat(rows[i].underlying, " twice on Ethereum"));
                found = true;
                assertEq(created.receiptVault, ethereum[j].receiptVault, string.concat(rows[i].underlying, " vault"));
                assertEq(
                    created.wrappedTokenVault,
                    ethereum[j].wrappedTokenVault,
                    string.concat(rows[i].underlying, " wrapper")
                );
            }
            assertTrue(found, string.concat(rows[i].underlying, " on Ethereum"));
        }
    }

    /// @notice The six rows no Base row carries are Ethereum's slots 42-47: the same vault, wrapper,
    /// symbol and name, and Ethereum's US authoriser, which their US region routes them to.
    function testOffBaseRowsAreEthereumSlots42To47() external view {
        TokenConfig[] memory rows = LibProdTokenConfig.canonicalTokenConfigs();
        EthereumSlot[6] memory slots = offBaseSlots();
        for (uint256 k = 0; k < slots.length; k++) {
            uint256 i = FIRST_OFF_BASE_SLOT + k;
            EthereumSlot memory slot = slots[k];
            TokenInstance memory created = sScript.callToken(i);
            assertEq(rows[i].underlying, slot.underlying, "underlying");
            assertEq(created.receiptVault, slot.vault, string.concat(slot.underlying, " vault"));
            assertEq(created.wrappedTokenVault, slot.wrapper, string.concat(slot.underlying, " wrapper"));
            assertEq(rows[i].symbol, slot.symbol, string.concat(slot.underlying, " symbol"));
            assertEq(rows[i].name, slot.name, string.concat(slot.underlying, " name"));
            assertEq(
                slot.authoriser,
                LibAuthoriserInvariants.authoriserForChainId(LibSafeInvariants.ETHEREUM_CHAIN_ID),
                string.concat(slot.underlying, " Ethereum authoriser")
            );
            assertEq(uint8(rows[i].region), uint8(Region.US), string.concat(slot.underlying, " region"));
        }
    }

    /// @notice No receipt, vault or wrapper the 0G creation makes is, in any other chain's production table, an
    /// address of a token with another underlying.
    /// Robinhood and BSC already put other underlyings at Ethereum's addresses, so 0G, which follows Ethereum, is
    /// held to the chains that share its order.
    function testNoZerogAddressIsAnotherUnderlyingOnEthereumOrHyperEvm() external view {
        TokenInstance[] memory zerog = zerogTokens();
        uint256[2] memory chainIds = [LibSafeInvariants.ETHEREUM_CHAIN_ID, LibSafeInvariants.HYPEREVM_CHAIN_ID];
        string[2] memory names = ["ethereum", "hyperevm"];
        uint256 shared = 0;
        for (uint256 n = 0; n < chainIds.length; n++) {
            TokenInstance[] memory other = LibTokenInvariants.productionTokensForChainId(chainIds[n]);
            for (uint256 i = 0; i < zerog.length; i++) {
                address[3] memory ours = legs(zerog[i]);
                for (uint256 j = 0; j < other.length; j++) {
                    address[3] memory theirs = legs(other[j]);
                    for (uint256 a = 0; a < 3; a++) {
                        for (uint256 b = 0; b < 3; b++) {
                            if (ours[a] != theirs[b]) continue;
                            assertEq(
                                other[j].underlying,
                                zerog[i].underlying,
                                string.concat(names[n], " ", vm.toString(ours[a]))
                            );
                            shared++;
                        }
                    }
                }
            }
        }
        assertGt(shared, 0, "no 0G address is on another chain");
    }
}
