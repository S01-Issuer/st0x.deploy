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
        uint256[6] memory chainIds = rolloutChainIds();
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

    function externalTokenCount(uint256 chainId) external pure returns (uint256) {
        return LibUnderlyingNamingRollout.tokenCount(chainId);
    }

    function externalRenamesRow(uint256 chainId, uint256 tokenIndex) external pure returns (bool) {
        return LibUnderlyingNamingRollout.renamesRow(chainId, tokenIndex);
    }

    /// On 0G the rollout renames 0G's own table, every row of its token
    /// creation, in its own order.
    function testZerogTokensAreItsWholeTable() external pure {
        TokenInstance[] memory table = LibTokenInvariants.productionTokensZerog();
        TokenInstance[] memory zerog = LibUnderlyingNamingRollout.tokens(LibSafeInvariants.ZEROG_CHAIN_ID);
        assertEq(table.length, LibUnderlyingNamingRollout.ZEROG_TOKEN_COUNT, "0G table");
        assertEq(zerog.length, table.length, "every 0G row");
        for (uint256 rowIndex = 0; rowIndex < table.length; rowIndex++) {
            assertSameToken(zerog[rowIndex], table[rowIndex]);
        }
    }

    /// `cutForChain` holds for exactly the deployment networks, on any chain
    /// id: not for a chain with no deployment, or an id no chain has.
    function testCutForChainIsExactlyTheDeploymentNetworks(uint256 chainId) external pure {
        bool deployed = chainId == LibSafeInvariants.BASE_CHAIN_ID || chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID
            || chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID || chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID
            || chainId == LibSafeInvariants.BSC_CHAIN_ID || chainId == LibSafeInvariants.ZEROG_CHAIN_ID;
        assertEq(LibUnderlyingNamingRollout.cutForChain(chainId), deployed);
        SupportedNetwork[] memory all = LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        assertEq(all.length, 6, "six deployment networks");
        for (uint256 networkIndex = 0; networkIndex < all.length; networkIndex++) {
            assertTrue(LibUnderlyingNamingRollout.cutForChain(all[networkIndex].chainId), all[networkIndex].name);
        }
        assertFalse(LibUnderlyingNamingRollout.cutForChain(0), "no chain");
        assertFalse(LibUnderlyingNamingRollout.cutForChain(137), "Polygon");
        assertFalse(LibUnderlyingNamingRollout.cutForChain(type(uint256).max), "max id");
    }

    /// `tokenCount` is 65 on 0G and 56 on every network before it, on any
    /// chain id, and refuses every chain the rollout was not cut for.
    function testTokenCountIsPerCutChain(uint256 chainId) external {
        assertEq(this.externalTokenCount(LibSafeInvariants.ZEROG_CHAIN_ID), 65, "0G");
        SupportedNetwork[] memory before =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.networksBeforeZerog());
        for (uint256 networkIndex = 0; networkIndex < before.length; networkIndex++) {
            assertEq(this.externalTokenCount(before[networkIndex].chainId), 56, before[networkIndex].name);
        }
        if (chainId == LibSafeInvariants.ZEROG_CHAIN_ID) {
            assertEq(this.externalTokenCount(chainId), LibUnderlyingNamingRollout.ZEROG_TOKEN_COUNT);
        } else if (LibRainDeploy.hasChainId(before, chainId)) {
            assertEq(this.externalTokenCount(chainId), LibUnderlyingNamingRollout.TOKEN_COUNT);
        } else {
            vm.expectRevert(abi.encodeWithSelector(UnderlyingNamingNotCutForChain.selector, chainId));
            this.externalTokenCount(chainId);
        }
    }

    /// The rollout serves every deployment network: each resolves the leading
    /// `tokenCount` rows of its own table.
    function testTokensServesEveryDeploymentNetwork() external view {
        SupportedNetwork[] memory all = LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 networkIndex = 0; networkIndex < all.length; networkIndex++) {
            uint256 chainId = all[networkIndex].chainId;
            TokenInstance[] memory chainTokens = this.externalTokens(chainId);
            TokenInstance[] memory table = LibTokenInvariants.productionTokensForChainId(chainId);
            assertEq(chainTokens.length, this.externalTokenCount(chainId), all[networkIndex].name);
            for (uint256 rowIndex = 0; rowIndex < chainTokens.length; rowIndex++) {
                assertSameToken(chainTokens[rowIndex], table[rowIndex]);
            }
        }
    }

    /// A table longer than the chain's count is cut to its leading rows, so a
    /// token appended later does not move the rename; a shorter one refuses,
    /// on 0G with its own count as on the networks before it.
    function testLeadingRowsCutsALongerTableAndRefusesAShorterOne() external {
        uint256[2] memory chainIds = [LibSafeInvariants.ETHEREUM_CHAIN_ID, LibSafeInvariants.ZEROG_CHAIN_ID];
        uint256[2] memory counts = [LibUnderlyingNamingRollout.TOKEN_COUNT, LibUnderlyingNamingRollout.ZEROG_TOKEN_COUNT];
        for (uint256 chainIndex = 0; chainIndex < chainIds.length; chainIndex++) {
            uint256 chainId = chainIds[chainIndex];
            uint256 count = counts[chainIndex];
            TokenInstance[] memory longer = new TokenInstance[](count + 1);
            for (uint256 rowIndex = 0; rowIndex < longer.length; rowIndex++) {
                longer[rowIndex].underlying = vm.toString(rowIndex);
            }
            TokenInstance[] memory cut = this.externalLeadingRows(chainId, longer);
            assertEq(cut.length, count, "cut length");
            assertEq(cut[count - 1].underlying, vm.toString(count - 1), "last kept row");

            TokenInstance[] memory shorter = new TokenInstance[](count - 1);
            vm.expectRevert(abi.encodeWithSelector(UnderlyingNamingTokenTableShort.selector, chainId, count, count - 1));
            this.externalLeadingRows(chainId, shorter);
        }
    }

    /// `leadingRows` and `renamesRow` refuse a chain the rollout was not cut
    /// for rather than cutting its table to another chain's count.
    function testLeadingRowsAndRenamesRowRefuseAnUncutChain() external {
        TokenInstance[] memory table = new TokenInstance[](LibUnderlyingNamingRollout.ZEROG_TOKEN_COUNT);
        vm.expectRevert(abi.encodeWithSelector(UnderlyingNamingNotCutForChain.selector, uint256(137)));
        this.externalLeadingRows(137, table);
        vm.expectRevert(abi.encodeWithSelector(UnderlyingNamingNotCutForChain.selector, uint256(137)));
        this.externalRenamesRow(137, 0);
    }

    function externalBeaconTokens(uint256 chainId) external pure returns (TokenInstance[] memory) {
        return LibUnderlyingNamingRollout.beaconTokens(chainId);
    }

    function externalUnrenamedTokens(uint256 chainId) external pure returns (TokenInstance[] memory) {
        return LibUnderlyingNamingRollout.unrenamedTokens(chainId);
    }

    function assertSameToken(TokenInstance memory actual, TokenInstance memory expected) internal pure {
        assertEq(actual.underlying, expected.underlying, "underlying");
        assertEq(actual.receipt, expected.receipt, string.concat(expected.underlying, " receipt"));
        assertEq(actual.receiptVault, expected.receiptVault, string.concat(expected.underlying, " receipt vault"));
        assertEq(actual.wrappedTokenVault, expected.wrappedTokenVault, string.concat(expected.underlying, " wrapper"));
    }

    function rolloutChainIds() internal pure returns (uint256[6] memory) {
        return [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID,
            LibSafeInvariants.ZEROG_CHAIN_ID
        ];
    }

    /// The rename skips the trailing rows of each table before 0G, and none of
    /// 0G's.
    function assertRenameCoverage(uint256 chainId, uint256 tableLength) internal pure {
        if (chainId == LibSafeInvariants.ZEROG_CHAIN_ID) {
            assertEq(tableLength, LibUnderlyingNamingRollout.ZEROG_TOKEN_COUNT, "0G renames its whole table");
        } else {
            assertGt(tableLength, LibUnderlyingNamingRollout.TOKEN_COUNT, "table has rows the rename skips");
        }
    }

    /// `beaconTokens` is the chain's whole table, rows the rename skips
    /// included, then tQSEP on Base and nothing more elsewhere.
    function testBeaconTokensAreTheTableThenTqsepOnBase() external pure {
        uint256[6] memory chainIds = rolloutChainIds();
        for (uint256 chainIndex = 0; chainIndex < chainIds.length; chainIndex++) {
            uint256 chainId = chainIds[chainIndex];
            TokenInstance[] memory table = LibTokenInvariants.productionTokensForChainId(chainId);
            TokenInstance[] memory beaconTokens = LibUnderlyingNamingRollout.beaconTokens(chainId);
            assertRenameCoverage(chainId, table.length);
            bool onBase = chainId == LibSafeInvariants.BASE_CHAIN_ID;
            assertEq(beaconTokens.length, table.length + (onBase ? 1 : 0), "length");
            for (uint256 rowIndex = 0; rowIndex < table.length; rowIndex++) {
                assertSameToken(beaconTokens[rowIndex], table[rowIndex]);
            }
            if (onBase) assertSameToken(beaconTokens[table.length], LibTokenInvariants.qsepToken());
        }
    }

    /// `unrenamedTokens` is `beaconTokens` without the vaults the rename batch
    /// targets, in order: the rows the rename skips, then tQSEP on Base. On 0G
    /// the rename targets every vault, so it is empty.
    function testUnrenamedTokensAreTheBeaconTokensTheRenameSkips() external pure {
        uint256[6] memory chainIds = rolloutChainIds();
        for (uint256 chainIndex = 0; chainIndex < chainIds.length; chainIndex++) {
            uint256 chainId = chainIds[chainIndex];
            (address[] memory targets,,) = LibUnderlyingNamingRollout.renameBatch(chainId);
            TokenInstance[] memory beaconTokens = LibUnderlyingNamingRollout.beaconTokens(chainId);
            TokenInstance[] memory unrenamed = LibUnderlyingNamingRollout.unrenamedTokens(chainId);
            uint256 next = 0;
            for (uint256 tokenIndex = 0; tokenIndex < beaconTokens.length; tokenIndex++) {
                bool targeted = false;
                for (uint256 targetIndex = 0; targetIndex < targets.length; targetIndex++) {
                    if (targets[targetIndex] == beaconTokens[tokenIndex].receiptVault) targeted = true;
                }
                if (!targeted) assertSameToken(unrenamed[next++], beaconTokens[tokenIndex]);
            }
            assertEq(unrenamed.length, next, "length");
            bool onBase = chainId == LibSafeInvariants.BASE_CHAIN_ID;
            if (chainId == LibSafeInvariants.ZEROG_CHAIN_ID) {
                assertEq(unrenamed.length, 0, "0G leaves no vault unrenamed");
            } else {
                assertGt(unrenamed.length, onBase ? 1 : 0, "table rows the rename skips");
            }
            if (onBase) assertSameToken(unrenamed[unrenamed.length - 1], LibTokenInvariants.qsepToken());
        }
    }

    /// Both token sets refuse a chain with no table rather than returning
    /// nothing.
    function testBeaconAndUnrenamedTokensRefuseAChainWithNoTable() external {
        vm.expectRevert(abi.encodeWithSelector(NoTokenTableForChain.selector, uint256(137)));
        this.externalBeaconTokens(137);
        vm.expectRevert(abi.encodeWithSelector(NoTokenTableForChain.selector, uint256(137)));
        this.externalUnrenamedTokens(137);
        vm.expectRevert(abi.encodeWithSelector(NoTokenTableForChain.selector, uint256(137)));
        this.externalTokens(137);
    }

    /// `renamesRow` holds for exactly the table rows whose vault the rename
    /// batch targets, and for no index past the table.
    function testRenamesRowIsTheRenameBatchTargets() external pure {
        uint256[6] memory chainIds = rolloutChainIds();
        for (uint256 chainIndex = 0; chainIndex < chainIds.length; chainIndex++) {
            uint256 chainId = chainIds[chainIndex];
            (address[] memory targets,,) = LibUnderlyingNamingRollout.renameBatch(chainId);
            TokenInstance[] memory table = LibTokenInvariants.productionTokensForChainId(chainId);
            for (uint256 rowIndex = 0; rowIndex < table.length; rowIndex++) {
                bool targeted = false;
                for (uint256 targetIndex = 0; targetIndex < targets.length; targetIndex++) {
                    if (targets[targetIndex] == table[rowIndex].receiptVault) targeted = true;
                }
                assertEq(LibUnderlyingNamingRollout.renamesRow(chainId, rowIndex), targeted, table[rowIndex].underlying);
            }
            assertFalse(LibUnderlyingNamingRollout.renamesRow(chainId, table.length), "past the table");
        }
    }
}
