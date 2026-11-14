// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    LibUnderlyingNamingRollout,
    MalformedUnderlying,
    DownstreamNotReadyForRename,
    UnderlyingNamingTokenTableShort
} from "../../../src/lib/LibUnderlyingNamingRollout.sol";
import {LibProdTokenConfig, TokenConfig, Region} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {MalformedUnderlyingIsin} from "../../../src/error/ErrUnderlying.sol";
import {NoTokenTableForChain, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";
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
            ticker: ticker,
            name: string.concat(underlyingName, " ST0x"),
            symbol: string.concat("t", ticker),
            region: Region.US,
            underlyingName: underlyingName,
            isin: isin
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

    /// The row check refuses a malformed current ISIN, naming it.
    function testRowCheckRefusesAMalformedIsin() external {
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingIsin.selector, "US67066G1041"));
        this.externalAssertUnderlyingWellFormed(row("US67066G1041", "NVDA", "NVIDIA Corporation"));

        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingIsin.selector, ""));
        this.externalAssertUnderlyingWellFormed(row("", "NVDA", "NVIDIA Corporation"));

        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingIsin.selector, "us67066g1040"));
        this.externalAssertUnderlyingWellFormed(row("us67066g1040", "NVDA", "NVIDIA Corporation"));
    }

    /// The current ISIN is checked, not the frozen listing `assetId`.
    function testRowCheckReadsTheCurrentIsin() external {
        TokenConfig memory config = row("US67066G1040", "NVDA", "NVIDIA Corporation");
        config.isin = "US67066G1041";
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingIsin.selector, "US67066G1041"));
        this.externalAssertUnderlyingWellFormed(config);
    }

    /// A malformed ticker is reported before a malformed ISIN on the same row.
    function testRowCheckReportsTickerBeforeIsin() external {
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlying.selector, "nvda", "NVIDIA Corporation"));
        this.externalAssertUnderlyingWellFormed(row("US67066G1041", "nvda", "NVIDIA Corporation"));
    }

    /// The row loop refuses a malformed ISIN on a row after well-formed ones.
    function testRowsCheckRefusesAMalformedIsinAmongGoodOnes() external {
        TokenConfig[] memory rows = new TokenConfig[](3);
        rows[0] = row("US67066G1040", "NVDA", "NVIDIA Corporation");
        rows[1] = row("US0378331005", "AAPL", "Apple Inc.");
        rows[2] = row("US5949181046", "MSFT", "Microsoft Corporation");
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingIsin.selector, "US5949181046"));
        this.externalAssertRowsWellFormed(rows);
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
}
