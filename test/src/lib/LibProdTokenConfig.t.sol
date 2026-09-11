// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.6.1/token/ERC20/extensions/IERC20Metadata.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
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
    /// `"Wrapped " + name` / `"w" + symbol` — pinning the derivation the
    /// deploy relies on (the wrapped leg takes no name/symbol input, so if
    /// this derivation ever changed the config table would be insufficient
    /// to reproduce Base's wrapped tokens).
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
}
