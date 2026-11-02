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
import {NoTokenTableForChain, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";
import {RUNTIME_CODE as RECEIPT_VAULT_RUNTIME_CODE} from "../../../src/generated/candidate/StoxReceiptVault.sol";
import {ScheduleUnderlyingNamingBeacons} from "../../../script/20261021-schedule-underlying-naming-beacons.s.sol";
import {ScheduleUnderlyingNamingRename} from "../../../script/20261021-schedule-underlying-naming-rename.s.sol";
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

    function row(string memory ticker, string memory underlyingName) internal pure returns (TokenConfig memory) {
        return TokenConfig({
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
        this.externalAssertUnderlyingWellFormed(row("NVDA", "NVIDIA Corporation"));

        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlying.selector, "tNVDA", "NVIDIA Corporation"));
        this.externalAssertUnderlyingWellFormed(row("tNVDA", "NVIDIA Corporation"));

        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlying.selector, "NVDA", "NVIDIA Corporation ST0x"));
        this.externalAssertUnderlyingWellFormed(row("NVDA", "NVIDIA Corporation ST0x"));

        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlying.selector, "NVDA", "NVIDIA \"Corp\""));
        this.externalAssertUnderlyingWellFormed(row("NVDA", "NVIDIA \"Corp\""));
    }

    function testTickerShape() external pure {
        assertTrue(LibUnderlyingNamingRollout.tickerWellFormed("NVDA"));
        assertTrue(LibUnderlyingNamingRollout.tickerWellFormed("BRK.B"));
        assertTrue(LibUnderlyingNamingRollout.tickerWellFormed("A"));
        assertTrue(LibUnderlyingNamingRollout.tickerWellFormed("ABCDEFGHIJKLMNOP"));
        assertFalse(LibUnderlyingNamingRollout.tickerWellFormed(""));
        assertFalse(LibUnderlyingNamingRollout.tickerWellFormed("ABCDEFGHIJKLMNOPQ"));
        assertFalse(LibUnderlyingNamingRollout.tickerWellFormed("tNVDA"));
        assertFalse(LibUnderlyingNamingRollout.tickerWellFormed("NV DA"));
        assertFalse(LibUnderlyingNamingRollout.tickerWellFormed("NV\"DA"));
        assertFalse(LibUnderlyingNamingRollout.tickerWellFormed("NV\\DA"));
    }

    function testNameShape() external pure {
        assertTrue(LibUnderlyingNamingRollout.nameWellFormed("NVIDIA Corporation"));
        assertTrue(LibUnderlyingNamingRollout.nameWellFormed(unicode"LVMH Moët Hennessy Louis Vuitton SE"));
        assertTrue(LibUnderlyingNamingRollout.nameWellFormed("Meta Platforms, Inc."));
        assertFalse(LibUnderlyingNamingRollout.nameWellFormed(""));
        assertFalse(LibUnderlyingNamingRollout.nameWellFormed("NVIDIA Corporation ST0x"));
        assertFalse(LibUnderlyingNamingRollout.nameWellFormed("NVIDIA Corporation (ST0x)"));
        assertFalse(LibUnderlyingNamingRollout.nameWellFormed("NVIDIA \"Corp\""));
        assertFalse(LibUnderlyingNamingRollout.nameWellFormed("NVIDIA\\Corp"));
        assertFalse(LibUnderlyingNamingRollout.nameWellFormed("NVIDIA\nCorp"));
        assertFalse(LibUnderlyingNamingRollout.nameWellFormed(hex"4e56494449417f"));
    }

    /// The boundaries the NatSpec states: digits 0 and 9 are tickers, the
    /// bytes either side are not; a space is the lowest name byte, 0x1f is
    /// not; a name shorter than the suffix is checked without underflow.
    function testShapeBoundaries() external pure {
        assertTrue(LibUnderlyingNamingRollout.tickerWellFormed("0"));
        assertTrue(LibUnderlyingNamingRollout.tickerWellFormed("9"));
        assertTrue(LibUnderlyingNamingRollout.tickerWellFormed("A0Z9."));
        assertFalse(LibUnderlyingNamingRollout.tickerWellFormed("/"));
        assertFalse(LibUnderlyingNamingRollout.tickerWellFormed(":"));
        assertFalse(LibUnderlyingNamingRollout.tickerWellFormed("@"));
        assertFalse(LibUnderlyingNamingRollout.tickerWellFormed("["));
        assertTrue(LibUnderlyingNamingRollout.nameWellFormed("3M"));
        assertTrue(LibUnderlyingNamingRollout.nameWellFormed(" "));
        assertFalse(LibUnderlyingNamingRollout.nameWellFormed(hex"1f"));
        assertFalse(LibUnderlyingNamingRollout.nameWellFormed("ST0x"));
    }

    /// With the release frozen but the downstream flag unset, the rename
    /// script refuses before it reads any chain state.
    function testRenameRefusesUntilDownstreamIsReady() external {
        assertFalse(LibUnderlyingNamingRollout.DOWNSTREAM_ACCEPTS_NEW_SYMBOLS);
        FrozenReleaseRenameHarness rename = new FrozenReleaseRenameHarness();
        vm.expectRevert(DownstreamNotReadyForRename.selector);
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
        rows[0] = row("NVDA", "NVIDIA Corporation");
        rows[1] = row("AAPL", "Apple Inc. ST0x");
        rows[2] = row("MSFT", "Microsoft Corporation");
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlying.selector, "AAPL", "Apple Inc. ST0x"));
        this.externalAssertRowsWellFormed(rows);
        rows[1] = row("AAPL", "Apple Inc.");
        this.externalAssertRowsWellFormed(rows);
    }

    /// The row loop checks the first and the last row: each one, as the only
    /// bad row, refuses. An empty list passes.
    function testRowsCheckCoversTheEndRows() external {
        TokenConfig[] memory rows = new TokenConfig[](3);
        rows[0] = row("NVDA", "NVIDIA \"Corp\"");
        rows[1] = row("AAPL", "Apple Inc.");
        rows[2] = row("MSFT", "Microsoft Corporation");
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlying.selector, "NVDA", "NVIDIA \"Corp\""));
        this.externalAssertRowsWellFormed(rows);

        rows[0] = row("NVDA", "NVIDIA Corporation");
        rows[2] = row("MSFT", "Microsoft Corporation (ST0x)");
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

    /// The release can only be frozen together with the record the freeze PR
    /// owes: while `RELEASE_FROZEN` is true, both schedule scripts must be
    /// declared migrations, so they record themselves in the registry.
    function testFreezingTheReleaseRequiresMigrationDeclarations() external {
        if (!LibUnderlyingNamingRollout.RELEASE_FROZEN) return;
        assertTrue(new ScheduleUnderlyingNamingBeacons().declaration().migration, "beacon batch is a migration");
        assertTrue(new ScheduleUnderlyingNamingRename().declaration().migration, "rename batch is a migration");
    }
}
