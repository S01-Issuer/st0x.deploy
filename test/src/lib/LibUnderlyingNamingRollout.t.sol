// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.43/src/lib/LibRainDeploy.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.43/src/lib/LibMigrationRegistryDeploy.sol";
import {
    LibUnderlyingNamingRollout,
    MalformedUnderlying,
    DownstreamNotReadyForRename,
    UnderlyingNamingNotCutForChain,
    UnderlyingNamingTokenTableShort
} from "../../../src/lib/LibUnderlyingNamingRollout.sol";
import {AssetId, AssetIdKind} from "../../../src/interface/IStoxTokenConfigV1.sol";
import {LibProdTokenConfig, TokenConfig, Region} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../../src/lib/LibStoxMigrations.sol";
import {LibLocalProdState} from "../../lib/LibLocalProdState.sol";
import {LibTestRootLine} from "../../lib/LibTestRootLine.sol";
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
            assetId: AssetId({kind: AssetIdKind.ISIN, id: isin}),
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

    /// 0G's leading `TOKEN_COUNT` rows hold a token Base's leading rows do
    /// not, so the rollout refuses 0G.
    function testTokensRefusesZerog() external {
        TokenInstance[] memory zerog = LibTokenInvariants.productionTokensForChainId(LibSafeInvariants.ZEROG_CHAIN_ID);
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        uint256 count = LibUnderlyingNamingRollout.TOKEN_COUNT;
        bool foundForeign = false;
        for (uint256 zerogRowIndex = 0; zerogRowIndex < count; zerogRowIndex++) {
            bool inBase = false;
            for (uint256 baseRowIndex = 0; baseRowIndex < count; baseRowIndex++) {
                if (
                    keccak256(bytes(zerog[zerogRowIndex].underlying)) == keccak256(bytes(base[baseRowIndex].underlying))
                ) inBase = true;
            }
            if (!inBase) foundForeign = true;
        }
        assertTrue(foundForeign, "0G's leading rows hold a token Base's do not");
        vm.expectRevert(
            abi.encodeWithSelector(UnderlyingNamingNotCutForChain.selector, LibSafeInvariants.ZEROG_CHAIN_ID)
        );
        this.externalTokens(LibSafeInvariants.ZEROG_CHAIN_ID);
    }

    /// `cutForChain` holds for exactly the five networks before 0G, on any
    /// chain id: not for 0G, a chain with no deployment, or an id no chain has.
    function testCutForChainIsExactlyTheNetworksBeforeZerog(uint256 chainId) external pure {
        bool historical = chainId == LibSafeInvariants.BASE_CHAIN_ID || chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID
            || chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID || chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID
            || chainId == LibSafeInvariants.BSC_CHAIN_ID;
        assertEq(LibUnderlyingNamingRollout.cutForChain(chainId), historical);
        assertFalse(LibUnderlyingNamingRollout.cutForChain(LibSafeInvariants.ZEROG_CHAIN_ID), "0G");
        assertFalse(LibUnderlyingNamingRollout.cutForChain(0), "no chain");
        assertFalse(LibUnderlyingNamingRollout.cutForChain(137), "Polygon");
        assertFalse(LibUnderlyingNamingRollout.cutForChain(type(uint256).max), "max id");
        assertEq(LibStoxDeployNetworks.networksBeforeZerog().length, 5, "five networks before 0G");
    }

    /// The rollout serves exactly the networks its batches were cut for: each
    /// one before 0G resolves its rows, and every other deployment network
    /// with a table refuses.
    function testTokensServesOnlyTheNetworksBeforeZerog() external view {
        SupportedNetwork[] memory before =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.networksBeforeZerog());
        for (uint256 networkIndex = 0; networkIndex < before.length; networkIndex++) {
            assertEq(this.externalTokens(before[networkIndex].chainId).length, LibUnderlyingNamingRollout.TOKEN_COUNT);
        }
        SupportedNetwork[] memory all = LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        uint256 refused = 0;
        for (uint256 networkIndex = 0; networkIndex < all.length; networkIndex++) {
            if (LibRainDeploy.hasChainId(before, all[networkIndex].chainId)) continue;
            try this.externalTokens(all[networkIndex].chainId) {
                revert(string.concat(all[networkIndex].name, " resolved"));
            } catch (bytes memory reason) {
                assertEq(
                    reason,
                    abi.encodeWithSelector(UnderlyingNamingNotCutForChain.selector, all[networkIndex].chainId),
                    all[networkIndex].name
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

    /// Each batch's last call writes its root-line record on every chain it was cut for: the beacon batch onto
    /// the Safe-owned Base vault handover, the rename batch onto the beacon batch's record.
    function testEachBatchEndsWithItsRootLineRecord() external {
        LibTestRootLine.etchRegistry(vm);
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.networksBeforeZerog());
        assertEq(networks.length, 5, "five chains");
        for (uint256 networkIndex = 0; networkIndex < networks.length; networkIndex++) {
            uint256 chainId = networks[networkIndex].chainId;
            string memory network = networks[networkIndex].name;
            uint256 snapshot = vm.snapshotState();
            LibLocalProdState.beacons(vm, chainId);
            (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
                LibUnderlyingNamingRollout.beaconBatch(chainId);
            vm.revertToState(snapshot);
            assertRecordLast(
                targets,
                values,
                payloads,
                LibTestRootLine.recordCalldata(
                    LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS,
                    LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK
                ),
                string.concat(network, ": beacon batch")
            );
            (targets, values, payloads) = LibUnderlyingNamingRollout.renameBatch(chainId);
            assertRecordLast(
                targets,
                values,
                payloads,
                LibTestRootLine.recordCalldata(
                    LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME,
                    LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS
                ),
                string.concat(network, ": rename batch")
            );
        }
    }

    function assertRecordLast(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        bytes memory record,
        string memory label
    ) internal pure {
        uint256 last = targets.length - 1;
        assertEq(targets[last], LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, label);
        assertEq(values[last], 0, label);
        assertEq(payloads[last], record, label);
        for (uint256 callIndex = 0; callIndex < last; callIndex++) {
            assertTrue(targets[callIndex] != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, label);
        }
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

    function rolloutChainIds() internal pure returns (uint256[5] memory) {
        return [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
    }

    /// `beaconTokens` is the chain's whole table, rows the rename skips
    /// included, then tQSEP on Base and nothing more elsewhere.
    function testBeaconTokensAreTheTableThenTqsepOnBase() external pure {
        uint256[5] memory chainIds = rolloutChainIds();
        for (uint256 chainIndex = 0; chainIndex < chainIds.length; chainIndex++) {
            uint256 chainId = chainIds[chainIndex];
            TokenInstance[] memory table = LibTokenInvariants.productionTokensForChainId(chainId);
            TokenInstance[] memory beaconTokens = LibUnderlyingNamingRollout.beaconTokens(chainId);
            assertGt(table.length, LibUnderlyingNamingRollout.TOKEN_COUNT, "table has rows the rename skips");
            bool onBase = chainId == LibSafeInvariants.BASE_CHAIN_ID;
            assertEq(beaconTokens.length, table.length + (onBase ? 1 : 0), "length");
            for (uint256 rowIndex = 0; rowIndex < table.length; rowIndex++) {
                assertSameToken(beaconTokens[rowIndex], table[rowIndex]);
            }
            if (onBase) assertSameToken(beaconTokens[table.length], LibTokenInvariants.qsepToken());
        }
    }

    /// `unrenamedTokens` is `beaconTokens` without the vaults the rename batch
    /// targets, in order: the rows the rename skips, then tQSEP on Base.
    function testUnrenamedTokensAreTheBeaconTokensTheRenameSkips() external {
        LibTestRootLine.etchRegistry(vm);
        uint256[5] memory chainIds = rolloutChainIds();
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
            assertGt(unrenamed.length, onBase ? 1 : 0, "table rows the rename skips");
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
    }

    /// `renamesRow` holds for exactly the table rows whose vault the rename batch targets.
    function testRenamesRowIsTheRenameBatchTargets() external {
        LibTestRootLine.etchRegistry(vm);
        uint256[5] memory chainIds = rolloutChainIds();
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
