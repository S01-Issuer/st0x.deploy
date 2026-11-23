// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {
    LibUnderlyingNamingRollout,
    MalformedUnderlying,
    DownstreamNotReadyForRename,
    UnderlyingNamingNotCutForChain,
    UnderlyingNamingTokenTableShort
} from "../../../src/lib/LibUnderlyingNamingRollout.sol";
import {LibProdTokenConfig, TokenConfig, Region} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTokenInvariants, NoTokenTableForChain, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";
import {RUNTIME_CODE as RECEIPT_VAULT_RUNTIME_CODE} from "../../../src/generated/candidate/StoxReceiptVault.sol";
import {DownstreamNotReadyRenameHarness} from "../../script/DownstreamNotReadyRenameHarness.sol";
import {FrozenReleaseRenameHarness} from "../../script/FrozenReleaseRenameHarness.sol";
import {ScheduleUnderlyingNamingRenameHarness} from "../../script/ScheduleUnderlyingNamingRenameHarness.sol";

contract LibUnderlyingNamingRolloutTest is Test {
    function externalAssertUnderlyingsWellFormed(uint256 chainId) external pure {
        LibUnderlyingNamingRollout.assertUnderlyingsWellFormed(chainId);
    }

    function externalAssertUnderlyingWellFormed(TokenConfig memory config) external pure {
        LibUnderlyingNamingRollout.assertUnderlyingWellFormed(config);
    }

    function externalAssertRowsWellFormed(TokenConfig[] memory rows) external pure {
        LibUnderlyingNamingRollout.assertRowsWellFormed(rows);
    }

    function externalLeadingRows(uint256 chainId, TokenInstance[] memory table)
        external
        pure
        returns (TokenInstance[] memory)
    {
        return LibUnderlyingNamingRollout.leadingRows(chainId, table);
    }

    function row(string memory isin, string memory ticker, string memory underlyingName)
        internal
        pure
        returns (TokenConfig memory)
    {
        return TokenConfig({
            assetId: isin,
            listingTicker: ticker,
            listingName: underlyingName,
            underlying: ticker,
            name: string.concat(underlyingName, " ST0x"),
            symbol: string.concat("t", ticker),
            region: Region.US,
            underlyingName: underlyingName
        });
    }

    /// Every row each chain's rename sets has a well-formed ticker and name.
    function testEveryChainsRowsAreWellFormed() external view {
        uint256[5] memory chainIds = [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
        for (uint256 chainIndex = 0; chainIndex < chainIds.length; chainIndex++) {
            this.externalAssertUnderlyingsWellFormed(chainIds[chainIndex]);
            TokenInstance[] memory chainTokens = LibUnderlyingNamingRollout.tokens(chainIds[chainIndex]);
            TokenConfig[] memory rows = new TokenConfig[](chainTokens.length);
            for (uint256 rowIndex = 0; rowIndex < chainTokens.length; rowIndex++) {
                rows[rowIndex] = LibProdTokenConfig.configOf(chainTokens[rowIndex].underlying);
            }
            this.externalAssertRowsWellFormed(rows);
        }
    }

    /// The row check refuses a malformed ticker or name, naming the row, and
    /// accepts a well-formed one.
    function testRowCheckRefusesEachMalformedField() external {
        this.externalAssertUnderlyingWellFormed(row("US67066G1040", "NVDA", "NVIDIA Corporation"));

        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlying.selector, "tNVDA", "NVIDIA Corporation"));
        this.externalAssertUnderlyingWellFormed(row("US67066G1040", "tNVDA", "NVIDIA Corporation"));

        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlying.selector, "NVDA", "NVIDIA Corporation ST0x"));
        this.externalAssertUnderlyingWellFormed(row("US67066G1040", "NVDA", "NVIDIA Corporation ST0x"));

        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlying.selector, "NVDA", "NVIDIA \"Corp\""));
        this.externalAssertUnderlyingWellFormed(row("US67066G1040", "NVDA", "NVIDIA \"Corp\""));
    }

    /// With the release frozen but the downstream flag unset, the rename
    /// script refuses before it reads any chain state.
    function testRenameRefusesUntilDownstreamIsReady() external {
        DownstreamNotReadyRenameHarness rename = new DownstreamNotReadyRenameHarness();
        vm.expectRevert(DownstreamNotReadyForRename.selector);
        rename.callPreflight();
    }

    /// The repo sets the downstream flag (RAI-4172), so once the release is
    /// frozen the rename script passes the downstream gate and goes on to the
    /// row check, which refuses here on a chain with no token table.
    function testRenamePassesTheDownstreamGateAsTheRepoSetsIt() external {
        assertTrue(LibUnderlyingNamingRollout.DOWNSTREAM_ACCEPTS_NEW_SYMBOLS);
        FrozenReleaseRenameHarness rename = new FrozenReleaseRenameHarness();
        vm.expectRevert(abi.encodeWithSelector(NoTokenTableForChain.selector, block.chainid));
        rename.callPreflight();
    }

    /// With both flags set, the pre-flight checks the rows before any chain
    /// read: on a chain with no token table, the row check is what refuses.
    function testRenamePreflightChecksRowsBeforeChainState() external {
        ScheduleUnderlyingNamingRenameHarness rename = new ScheduleUnderlyingNamingRenameHarness("offline");
        vm.expectRevert(abi.encodeWithSelector(NoTokenTableForChain.selector, block.chainid));
        rename.callPreflight();
    }

    /// The receipt-vault implementation the rollout upgrades to delegatecalls
    /// the facet the beacon pre-flight checks: its pinned runtime code has the
    /// rollout's facet address compiled in. Re-pointing one constant without
    /// the other fails here, not after signing and the delay.
    function testReceiptVaultCallsTheRolloutFacet() external pure {
        assertEq(keccak256(RECEIPT_VAULT_RUNTIME_CODE), LibUnderlyingNamingRollout.RECEIPT_VAULT_CODEHASH, "codehash");
        bytes memory code = RECEIPT_VAULT_RUNTIME_CODE;
        bytes20 facet = bytes20(LibUnderlyingNamingRollout.FACET);
        bool found = false;
        for (uint256 byteIndex = 0; byteIndex + 20 <= code.length && !found; byteIndex++) {
            bytes20 window;
            assembly ("memory-safe") {
                window := mload(add(add(code, 0x20), byteIndex))
            }
            found = window == facet;
        }
        assertTrue(found, "facet address in vault code");
    }

    /// The row loop refuses the first malformed row, after well-formed ones.
    function testRowsCheckRefusesAMalformedRowAmongGoodOnes() external {
        TokenConfig[] memory rows = new TokenConfig[](3);
        rows[0] = row("US67066G1040", "NVDA", "NVIDIA Corporation");
        rows[1] = row("US0378331005", "AAPL", "Apple Inc. ST0x");
        rows[2] = row("US5949181045", "MSFT", "Microsoft Corporation");
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlying.selector, "AAPL", "Apple Inc. ST0x"));
        this.externalAssertRowsWellFormed(rows);
        rows[1] = row("US0378331005", "AAPL", "Apple Inc.");
        this.externalAssertRowsWellFormed(rows);
    }

    /// The row loop checks the first and the last row: each one, as the only
    /// bad row, refuses. An empty list passes.
    function testRowsCheckCoversTheEndRows() external {
        TokenConfig[] memory rows = new TokenConfig[](3);
        rows[0] = row("US67066G1040", "NVDA", "NVIDIA \"Corp\"");
        rows[1] = row("US0378331005", "AAPL", "Apple Inc.");
        rows[2] = row("US5949181045", "MSFT", "Microsoft Corporation");
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlying.selector, "NVDA", "NVIDIA \"Corp\""));
        this.externalAssertRowsWellFormed(rows);

        rows[0] = row("US67066G1040", "NVDA", "NVIDIA Corporation");
        rows[2] = row("US5949181045", "MSFT", "Microsoft Corporation (ST0x)");
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlying.selector, "MSFT", "Microsoft Corporation (ST0x)"));
        this.externalAssertRowsWellFormed(rows);

        this.externalAssertRowsWellFormed(new TokenConfig[](0));
    }

    function externalTokens(uint256 chainId) external pure returns (TokenInstance[] memory) {
        return LibUnderlyingNamingRollout.tokens(chainId);
    }

    /// 0G's table is hydrated, but its leading `TOKEN_COUNT` rows hold a
    /// token that Base's leading rows do not, so the rollout refuses 0G
    /// rather than rename another token set.
    function testTokensRefusesZerog() external {
        TokenInstance[] memory zerog = LibTokenInvariants.productionTokensForChainId(LibSafeInvariants.ZEROG_CHAIN_ID);
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        uint256 count = LibUnderlyingNamingRollout.TOKEN_COUNT;
        bool foundForeign = false;
        for (uint256 z = 0; z < count; z++) {
            bool inBase = false;
            for (uint256 b = 0; b < count; b++) {
                if (keccak256(bytes(zerog[z].underlying)) == keccak256(bytes(base[b].underlying))) inBase = true;
            }
            if (!inBase) foundForeign = true;
        }
        assertTrue(foundForeign, "0G's leading rows hold a token Base's do not");
        vm.expectRevert(
            abi.encodeWithSelector(UnderlyingNamingNotCutForChain.selector, LibSafeInvariants.ZEROG_CHAIN_ID)
        );
        this.externalTokens(LibSafeInvariants.ZEROG_CHAIN_ID);
    }

    /// The rollout serves exactly the networks its batches were cut for: each
    /// one before 0G resolves its rows, and every other deployment network
    /// with a table refuses.
    function testTokensServesOnlyTheNetworksBeforeZerog() external view {
        SupportedNetwork[] memory before =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.networksBeforeZerog());
        for (uint256 i = 0; i < before.length; i++) {
            assertEq(this.externalTokens(before[i].chainId).length, LibUnderlyingNamingRollout.TOKEN_COUNT);
        }
        SupportedNetwork[] memory all = LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        uint256 refused = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (LibRainDeploy.hasChainId(before, all[i].chainId)) continue;
            assertTrue(LibTokenInvariants.tokenTableHydrated(all[i].chainId), all[i].name);
            try this.externalTokens(all[i].chainId) {
                revert(string.concat(all[i].name, " resolved"));
            } catch (bytes memory reason) {
                assertEq(
                    reason, abi.encodeWithSelector(UnderlyingNamingNotCutForChain.selector, all[i].chainId), all[i].name
                );
            }
            refused++;
        }
        assertEq(refused, all.length - before.length, "every later network refuses");
        assertGt(refused, 0, "0G is a later network");
    }

    /// A table longer than `TOKEN_COUNT` is cut to its leading rows, so a
    /// token appended later does not move the rename; a shorter one refuses.
    function testLeadingRowsCutsALongerTableAndRefusesAShorterOne() external {
        uint256 count = LibUnderlyingNamingRollout.TOKEN_COUNT;
        TokenInstance[] memory longer = new TokenInstance[](count + 1);
        for (uint256 rowIndex = 0; rowIndex < longer.length; rowIndex++) {
            longer[rowIndex].underlying = vm.toString(rowIndex);
        }
        TokenInstance[] memory cut = this.externalLeadingRows(1, longer);
        assertEq(cut.length, count, "cut length");
        assertEq(cut[count - 1].underlying, vm.toString(count - 1), "last kept row");

        TokenInstance[] memory shorter = new TokenInstance[](count - 1);
        vm.expectRevert(abi.encodeWithSelector(UnderlyingNamingTokenTableShort.selector, uint256(1), count, count - 1));
        this.externalLeadingRows(1, shorter);
    }

    /// `renamesRow` holds for exactly the table rows whose vault the rename batch targets.
    function testRenamesRowIsTheRenameBatchTargets() external pure {
        uint256[5] memory chainIds = [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
        for (uint256 chainIndex = 0; chainIndex < chainIds.length; chainIndex++) {
            (address[] memory targets,,) = LibUnderlyingNamingRollout.renameBatch(chainIds[chainIndex]);
            TokenInstance[] memory table = LibTokenInvariants.productionTokensForChainId(chainIds[chainIndex]);
            for (uint256 rowIndex = 0; rowIndex < table.length; rowIndex++) {
                bool targeted = false;
                for (uint256 targetIndex = 0; targetIndex < targets.length; targetIndex++) {
                    if (targets[targetIndex] == table[rowIndex].receiptVault) targeted = true;
                }
                assertEq(LibUnderlyingNamingRollout.renamesRow(rowIndex), targeted, table[rowIndex].underlying);
            }
        }
    }
}
