// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {LibRainDeploy} from "rain-deploy-0.1.25/src/lib/LibRainDeploy.sol";
import {LibProdTokenConfig, TokenConfig, Region, UnknownUnderlying} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibTokenInvariants, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";

/// @title LibProdTokenConfigTest
/// @notice Pins the deploy-input token config against two sources of truth:
/// the deployed Base address table (order + keys must align) and — on a
/// Base fork — the live receipt vaults themselves (the captured name/symbol
/// must equal what Base actually reports, so a typo or a stale capture
/// fails here rather than silently producing a mismatched token on the new
/// chain). This is what makes the config a trustworthy cross-chain baseline:
/// the parity pin asserts every chain against this table, and this test
/// asserts the table against live Base.
contract LibProdTokenConfigTest is Test {
    /// The config table and the Base address table pair by index over every
    /// row Base carries: same `underlying` in the same order. The config table
    /// may run AHEAD of Base — a row is authored when a ticker is chosen and
    /// Base is pinned when its deploy lands, and `_selectMissing` reads only
    /// the rows Base carries — but a config table SHORTER than Base would
    /// leave a deployed token with no name/symbol to copy, so that is the
    /// failure.
    function testConfigAlignsWithBaseTokenTable() external pure {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensBase();
        assertGe(configs.length, tokens.length, "config table shorter than Base table");
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(configs[i].underlying, tokens[i].underlying, "underlying order/key mismatch");
        }
    }

    /// No `underlying` appears twice in the config table — guards the
    /// ahead-of-Base window, where a ticker authored early could be appended
    /// a second time when its Base deploy is pinned.
    function testConfigHasNoDuplicateUnderlyings() external pure {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 i = 0; i < configs.length; i++) {
            for (uint256 j = i + 1; j < configs.length; j++) {
                assertNotEq(
                    keccak256(bytes(configs[i].underlying)),
                    keccak256(bytes(configs[j].underlying)),
                    string.concat("duplicate config underlying: ", configs[i].underlying)
                );
            }
        }
    }

    /// Every config's name/symbol equals the live Base receipt vault's —
    /// the exact-match guarantee that lets the new chain reproduce Base.
    /// Runs on a Base fork.
    function testConfigMatchesLiveBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensBase();
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20Metadata vault = IERC20Metadata(tokens[i].receiptVault);
            assertEq(
                configs[i].name, vault.name(), string.concat(configs[i].underlying, ": config name != live Base name")
            );
            assertEq(
                configs[i].symbol,
                vault.symbol(),
                string.concat(configs[i].underlying, ": config symbol != live Base symbol")
            );
        }
    }

    /// The wrapped vault's derived name/symbol on Base are exactly
    /// `"Wrapped " + name` / `"w" + symbol` — the derivation that applies
    /// while the receipt vault's underlying ticker and name are unset. The
    /// wrapped leg takes no name/symbol input, so this pins that the config
    /// table alone reproduces Base's wrapped tokens in that state.
    function testWrappedDerivationHoldsOnBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensBase();
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20Metadata wrapped = IERC20Metadata(tokens[i].wrappedTokenVault);
            assertEq(
                wrapped.name(),
                string.concat("Wrapped ", configs[i].name),
                string.concat(configs[i].underlying, ": wrapped name derivation drift")
            );
            assertEq(
                wrapped.symbol(),
                string.concat("w", configs[i].symbol),
                string.concat(configs[i].underlying, ": wrapped symbol derivation drift")
            );
        }
    }

    /// Every row's symbol is "t" + its underlying key, so a `setUnderlying`
    /// batch that takes the ticker from `underlying` leaves each receipt
    /// vault's `symbol()` unchanged.
    function testSymbolIsTPlusUnderlying() external pure {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        assertGt(configs.length, 0);
        for (uint256 rowIndex = 0; rowIndex < configs.length; rowIndex++) {
            assertGt(bytes(configs[rowIndex].underlying).length, 0, "empty underlying");
            assertEq(
                configs[rowIndex].symbol, string.concat("t", configs[rowIndex].underlying), configs[rowIndex].underlying
            );
        }
    }

    function testRegionOf() external pure {
        assertEq(uint8(LibProdTokenConfig.regionOf("MC")), uint8(Region.EU));
        assertEq(uint8(LibProdTokenConfig.regionOf("SNES")), uint8(Region.US));
    }

    function externalRegionOf(string memory underlying) external pure returns (Region) {
        return LibProdTokenConfig.regionOf(underlying);
    }

    function externalConfigOf(string memory underlying) external pure returns (TokenConfig memory) {
        return LibProdTokenConfig.configOf(underlying);
    }

    /// `configOf` refuses a key with no row, including near misses.
    function testConfigOfUnknownUnderlyingReverts() external {
        vm.expectRevert(abi.encodeWithSelector(UnknownUnderlying.selector, "MC.PA"));
        this.externalConfigOf("MC.PA");
        vm.expectRevert(abi.encodeWithSelector(UnknownUnderlying.selector, ""));
        this.externalConfigOf("");
        vm.expectRevert(abi.encodeWithSelector(UnknownUnderlying.selector, "nvda"));
        this.externalConfigOf("nvda");
    }

    /// `configOf` returns every row by its own key.
    function testConfigOfReturnsEveryRowByItsKey() external pure {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 rowIndex = 0; rowIndex < configs.length; rowIndex++) {
            TokenConfig memory found = LibProdTokenConfig.configOf(configs[rowIndex].underlying);
            assertEq(found.underlying, configs[rowIndex].underlying);
            assertEq(found.name, configs[rowIndex].name);
            assertEq(found.symbol, configs[rowIndex].symbol);
            assertEq(found.underlyingName, configs[rowIndex].underlyingName);
            assertEq(uint8(found.region), uint8(configs[rowIndex].region));
        }
    }

    function testRegionOfUnknownUnderlyingReverts() external {
        vm.expectRevert(abi.encodeWithSelector(UnknownUnderlying.selector, "MC.PA"));
        this.externalRegionOf("MC.PA");
    }
}
