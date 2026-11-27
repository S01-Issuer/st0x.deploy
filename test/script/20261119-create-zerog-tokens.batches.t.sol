// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.7.0/proxy/utils/Initializable.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibSafeTx, SafeTx} from "rain-deploy-0.1.41/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.41/src/lib/LibSafeFork.sol";
import {ICloneableV2} from "rain-factory-0.2.20/src/interface/ICloneableV2.sol";
import {
    OffchainAssetReceiptVault,
    OffchainAssetReceiptVaultConfigV2
} from "rain-vats-0.2.25/src/abstract/OffchainAssetReceiptVault.sol";
import {DEPOSIT} from "rain-vats-0.2.25/src/abstract/OffchainAssetReceiptVault.sol";
import {ReceiptVaultConfigV2} from "rain-vats-0.2.25/src/abstract/ReceiptVault.sol";
import {IAuthorizeV1, Unauthorized} from "rain-vats-0.2.25/src/interface/IAuthorizeV1.sol";

import {
    createZerogTokensDeclaration,
    ZerogDeployersOutOfStep,
    ZerogTokenMismatch,
    ZerogTokensRecordedEarly
} from "../../script/20261119-create-zerog-tokens.s.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {IAuthorisable} from "../../src/interface/IAuthorisable.sol";
import {IStoxUnifiedDeployerV1} from "../../src/interface/IStoxUnifiedDeployerV1.sol";
import {
    IStoxWrappedTokenVaultBeaconSetDeployerV1
} from "../../src/interface/IStoxWrappedTokenVaultBeaconSetDeployerV1.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {CreateZerogTokensHarness} from "./CreateZerogTokensHarness.sol";
import {ZerogTokenCreationFixture} from "./ZerogTokenCreationFixture.sol";

/// @title CreateZerogTokensBatchesTest
/// @notice On 0G with the line at its onto, four bundles create every 0G row in creation order, each under 0G's 36M
/// block, each handing its vaults to the timelock on their region's authoriser, and only the one that creates the last
/// row records the migration.
contract CreateZerogTokensBatchesTest is ZerogTokenCreationFixture {
    /// @notice The EIP-7825 per-transaction gas cap, 2^24. A batch under it lands whether or not 0G enforces the cap,
    /// and uses under half of 0G's 36M block.
    uint256 internal constant MAX_BATCH_GAS = 16_777_216;

    /// @notice One whole token, as the issuer would mint it.
    uint256 internal constant AMOUNT = 1e18;

    /// @notice 65 rows at 20 per bundle.
    uint256 internal constant BATCH_COUNT = 4;

    /// @notice keccak256 of the `multiSend(bytes)` calldata of the first bundle, as signed on 0G.
    bytes32 internal constant SIGNED_FIRST_BATCH_MULTISEND_HASH =
        0xdd2eca03073fa245241174defa8756352964524c0cc8ae1479ac3bb2c1ae5e39;

    CreateZerogTokensHarness internal sScript;

    function setUp() external {
        buildZerog();
        landZerogBackfill();
        sScript = new CreateZerogTokensHarness("batches");
    }

    function safe() internal pure returns (address) {
        return LibSafeInvariants.safeForChainId(LibSafeInvariants.ZEROG_CHAIN_ID);
    }

    function timelock() internal pure returns (address) {
        return LibTimelockInvariants.timelockForChainId(LibSafeInvariants.ZEROG_CHAIN_ID);
    }

    /// @dev External so a test can expect the Safe execution to revert.
    function executeAsSafe(SafeTx[] memory txs) external {
        LibSafeFork.executeBundle(vm, Safe(payable(safe())), txs);
    }

    function executeNextBatch() internal returns (SafeTx[] memory, uint256) {
        sScript.callPreflight();
        SafeTx[] memory txs = sScript.callAuthorBundle();
        uint256 before = gasleft();
        LibSafeFork.executeBundle(vm, Safe(payable(safe())), txs);
        uint256 gasUsed = before - gasleft();
        sScript.callAssertPostState();
        return (txs, gasUsed);
    }

    function executeAllBatches() internal {
        for (uint256 batch = 0; batch < BATCH_COUNT; batch++) {
            executeNextBatch();
        }
    }

    /// @notice What anyone can call on the public 0.1.1 unified deployer: `row`'s exact config, owned by `admin`.
    function createAs(address caller, address admin, TokenConfig memory row) internal {
        vm.prank(caller);
        IStoxUnifiedDeployerV1(LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1)
            .newTokenAndWrapperVault(
                OffchainAssetReceiptVaultConfigV2({
                initialAdmin: admin,
                receiptVaultConfig: ReceiptVaultConfigV2({
                asset: address(0), name: row.name, symbol: row.symbol, receipt: address(0)
            })
            })
            );
    }

    function rows() internal pure returns (TokenConfig[] memory) {
        return LibProdTokenConfig.canonicalTokenConfigs();
    }

    function firstRowIn(Region region) internal pure returns (uint256) {
        TokenConfig[] memory all = rows();
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].region == region) return i;
        }
        revert("no row in the region");
    }

    /// @notice 65 rows land as 20, 20, 20 and 5, and only the last bundle carries the record, as its final entry.
    function testFourBatchesOf20And5CreateEveryRowAndOnlyTheLastRecords() external {
        // Two probes, then three entries per row; the last batch adds the record.
        uint256[BATCH_COUNT] memory expectedTxs = [uint256(2 + 3 * 20), 2 + 3 * 20, 2 + 3 * 20, 2 + 3 * 5 + 1];
        uint256[BATCH_COUNT] memory expectedCreated = [uint256(20), 40, 60, 65];
        SafeTx memory record = LibStoxMigrations.recordTx(createZerogTokensDeclaration());
        bytes32 recordHash = keccak256(abi.encode(record));
        for (uint256 batch = 0; batch < BATCH_COUNT; batch++) {
            (SafeTx[] memory txs, uint256 gasUsed) = executeNextBatch();
            emit log_named_uint("batch gas", gasUsed);
            assertEq(txs.length, expectedTxs[batch], "batch length");
            assertLt(gasUsed, MAX_BATCH_GAS, "batch gas");
            assertEq(sScript.callCreatedCount(), expectedCreated[batch], "rows created");
            bool last = batch == BATCH_COUNT - 1;
            for (uint256 i = 0; i < txs.length; i++) {
                bool isRecord = keccak256(abi.encode(txs[i])) == recordHash;
                assertEq(isRecord, last && i == txs.length - 1, "record only as the last bundle's final entry");
            }
            if (!last) {
                assertEq(LibStoxMigrations.applied(LibStoxMigrations.CREATE_ZEROG_TOKENS), 0, "not recorded yet");
                assertEq(
                    LibStoxMigrations.head(), LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5, "line at the backfill"
                );
            }
        }
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.CREATE_ZEROG_TOKENS, "recorded with the last row");
    }

    /// @notice The first bundle, rows 0-19, is byte for byte the one already signed on 0G.
    function testFirstBatchIsTheSignedBundle() external view {
        assertEq(sScript.callCreatedCount(), 0, "no row created yet");
        assertEq(
            keccak256(LibSafeTx.encodeMultiSend(sScript.callAuthorBundle())),
            SIGNED_FIRST_BATCH_MULTISEND_HASH,
            "first bundle as signed"
        );
    }

    /// @notice After each batch, every token created so far is the timelock's on its region's authoriser, and the
    /// Safe owns none: no vault waits on a later bundle or a timelock operation to be wired.
    function testEachBatchHandsItsVaultsToTheTimelockOnTheirRegionsAuthoriser() external {
        TokenConfig[] memory all = rows();
        for (uint256 batch = 0; batch < BATCH_COUNT; batch++) {
            executeNextBatch();
            uint256 created = sScript.callCreatedCount();
            for (uint256 i = 0; i < created; i++) {
                address vault = sScript.callToken(i).receiptVault;
                assertEq(Ownable(vault).owner(), timelock(), all[i].underlying);
                address expected = all[i].region == Region.EU
                    ? LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid)
                    : LibAuthoriserInvariants.authoriserForChainId(block.chainid);
                assertEq(IAuthorisable(vault).authorizer(), expected, all[i].underlying);
            }
        }
    }

    /// @notice The end state is the repo's production invariants over the 0G tokens: every vault owned by the
    /// timelock and on its region's authoriser, both authorisers holding their role maps with the timelock as admin,
    /// and the Safe unable to touch any vault directly.
    function testFinalStateMeetsTheProductionInvariants() external {
        executeAllBatches();
        TokenInstance[] memory table = new TokenInstance[](rows().length);
        for (uint256 i = 0; i < table.length; i++) {
            table[i] = sScript.callToken(i);
        }
        LibTokenInvariants.assertUniformOwnership(table, timelock());
        LibTokenInvariants.assertUniformAuthoriser(table, LibAuthoriserInvariants.authoriserForChainId(block.chainid));
        address us = LibAuthoriserInvariants.authoriserForChainId(block.chainid);
        LibAuthoriserInvariants.assertHeld(
            us, LibAuthoriserInvariants.expectedGrantsWithoutOrchestrator(safe(), timelock())
        );
        assertFalse(
            IAccessControl(us).hasRole(DEPOSIT, LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR), "no orchestrator deposit"
        );
        LibAuthoriserInvariants.assertExpectedEuGrants(
            LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid),
            timelock(),
            LibAuthoriserInvariants.GRANTEE_EU_MINTER
        );
        // A well-formed authoriser, so the vault's own check on it passes and `onlyOwner` decides.
        IAuthorizeV1 other = IAuthorizeV1(LibAuthoriserInvariants.authoriserForChainId(block.chainid));
        for (uint256 i = 0; i < table.length; i++) {
            vm.prank(safe());
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, safe()));
            OffchainAssetReceiptVault(payable(table[i].receiptVault)).setAuthorizer(other);
        }
    }

    /// @notice Once the bundles land, the Safe can mint and redeem a US token: its `DEPOSIT`, `WITHDRAW` and
    /// `CERTIFY` on the V4 clone pass the vault's authoriser. The orchestrator, which 0G's clone does
    /// not grant, is refused, as is anyone else.
    function testSafeCanMintAUsTokenAfterTheBundles() external {
        executeAllBatches();
        OffchainAssetReceiptVault vault =
            OffchainAssetReceiptVault(payable(sScript.callToken(firstRowIn(Region.US)).receiptVault));
        vm.prank(safe());
        vault.certify(block.timestamp + 1 days, false, "");
        mintAndRedeem(vault, safe());
        assertMintRefused(vault, LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR);
        assertMintRefused(vault, address(0xBEEF));
    }

    /// @notice A token from the first bundle can mint before the second bundle: its supply does not stop the later
    /// pre-flights and post-states, which require an empty supply only on the rows their own bundle creates.
    function testAMintBetweenBundlesDoesNotStopTheNext() external {
        executeNextBatch();
        uint256 row = firstRowIn(Region.US);
        assertLt(row, 20, "first bundle row");
        OffchainAssetReceiptVault vault = OffchainAssetReceiptVault(payable(sScript.callToken(row).receiptVault));
        vm.startPrank(safe());
        vault.certify(block.timestamp + 1 days, false, "");
        vault.mint(AMOUNT, safe(), 0, "");
        vm.stopPrank();
        for (uint256 batch = 1; batch < BATCH_COUNT; batch++) {
            executeNextBatch();
        }
        assertEq(vault.totalSupply(), AMOUNT, "still minted");
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.CREATE_ZEROG_TOKENS, "recorded");
    }

    /// @notice An EU token mints through the EU clone: its minter's `CERTIFY`, `DEPOSIT` and `WITHDRAW` pass, and the
    /// US orchestrator, which holds no role there, is refused.
    function testEuMinterCanMintAnEuTokenAfterTheBundles() external {
        executeAllBatches();
        OffchainAssetReceiptVault vault =
            OffchainAssetReceiptVault(payable(sScript.callToken(firstRowIn(Region.EU)).receiptVault));
        vm.prank(LibAuthoriserInvariants.GRANTEE_EU_MINTER);
        vault.certify(block.timestamp + 1 days, false, "");
        mintAndRedeem(vault, LibAuthoriserInvariants.GRANTEE_EU_MINTER);
        assertMintRefused(vault, LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR);
    }

    function mintAndRedeem(OffchainAssetReceiptVault vault, address minter) internal {
        vm.prank(minter);
        assertEq(vault.mint(AMOUNT, minter, 0, ""), AMOUNT, "1:1 share ratio");
        assertEq(vault.balanceOf(minter), AMOUNT, "minted");
        uint256 id = vault.highwaterId();
        vm.prank(minter);
        vault.redeem(AMOUNT, minter, minter, id, "");
        assertEq(vault.balanceOf(minter), 0, "redeemed");
    }

    function assertMintRefused(OffchainAssetReceiptVault vault, address user) internal {
        vm.prank(user);
        (bool ok, bytes memory reason) = address(vault).call(abi.encodeCall(vault.mint, (AMOUNT, user, 0, "")));
        assertFalse(ok, "mint must revert");
        // The revert's trailing `data` is the encoded state change, so only the user and permission are compared.
        bytes memory head = abi.encodeWithSelector(Unauthorized.selector, user, DEPOSIT);
        assertGe(reason.length, head.length);
        for (uint256 i = 0; i < head.length; i++) {
            assertEq(reason[i], head[i], "Unauthorized(user, DEPOSIT)");
        }
    }

    function testPostStateOfAnEarlyBatchRefusesItsRecord() external {
        executeNextBatch();
        LibTestRootLine.write(
            vm, safe(), LibStoxMigrations.CREATE_ZEROG_TOKENS, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5
        );
        vm.expectRevert(
            abi.encodeWithSelector(ZerogTokensRecordedEarly.selector, LibStoxMigrations.CREATE_ZEROG_TOKENS)
        );
        sScript.callAssertPostState();
    }

    /// @notice Anyone may call the 0.1.1 unified deployer. A token it creates for another config takes the next row's
    /// place, and the pre-flight refuses rather than pairing it with that row.
    function testPreflightRefusesAnotherCallersToken() external {
        executeNextBatch();
        createAs(address(0xBEEF), address(0xBEEF), rows()[20]);
        vm.expectRevert(abi.encodeWithSelector(ZerogTokenMismatch.selector, rows()[20].underlying, "owner"));
        sScript.callPreflight();
    }

    /// @notice A receipt and vault created without their wrapper leave the deployers out of step.
    function testPreflightRefusesAVaultWithoutItsWrapper() external {
        executeNextBatch();
        vm.prank(address(0xBEEF));
        (bool ok,) = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1
            .call(
                abi.encodeWithSignature(
                    "newOffchainAssetReceiptVault((address,(address,string,string,address)))",
                    OffchainAssetReceiptVaultConfigV2({
                        initialAdmin: address(0xBEEF),
                        receiptVaultConfig: ReceiptVaultConfigV2({
                            asset: address(0), name: "x", symbol: "x", receipt: address(0)
                        })
                    })
                )
            );
        assertTrue(ok, "vault created");
        vm.expectRevert(abi.encodeWithSelector(ZerogDeployersOutOfStep.selector, uint256(3 + 2 * 21), uint256(1 + 20)));
        sScript.callPreflight();
    }

    /// @dev External so a test can expect one bundle entry, called as the Safe, to revert with its own reason.
    function callAsSafe(SafeTx memory entry) external {
        LibSafeFork.simulateCall(vm, Safe(payable(safe())), entry.to, entry.data);
    }

    /// @notice What the Safe reverts with when an entry of its bundle reverts.
    function gs013() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", "GS013");
    }

    /// @notice The bundle's first entry is the vault probe at row 20's predicted vault, which the front-run took, and
    /// it refuses: the vault there is already initialised. A MultiSend stops at its first failing entry, so the
    /// probe, and nothing later in the bundle, is what reverts it.
    function assertTheVaultProbeRefuses(SafeTx[] memory txs) internal {
        assertEq(txs[0].to, sScript.callToken(20).receiptVault, "first entry probes the next vault");
        assertEq(txs[0].data, abi.encodeCall(ICloneableV2.initialize, ("")), "first entry is the probe");
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        this.callAsSafe(txs[0]);
    }

    /// @notice A creation that lands after the bundle is authored and before it executes moves every predicted
    /// address. Even a copy of the next row that names the Safe as owner, which the Safe could wire, reverts the whole
    /// bundle at its vault probe, and the next pre-flight refuses the foreign token.
    function testFrontRunAfterAuthoringRevertsTheWholeBundle() external {
        executeNextBatch();
        SafeTx[] memory txs = sScript.callAuthorBundle();
        createAs(address(0xBEEF), safe(), rows()[20]);
        assertTheVaultProbeRefuses(txs);
        vm.expectRevert(gs013());
        this.executeAsSafe(txs);
        assertEq(sScript.callCreatedCount(), 21, "only the front-run's token");
        assertEq(Ownable(sScript.callToken(20).receiptVault).owner(), safe(), "front-run token untouched");
        vm.expectRevert(abi.encodeWithSelector(ZerogTokenMismatch.selector, rows()[20].underlying, "owner"));
        sScript.callPreflight();
    }

    /// @notice A wrapper created alone after the bundle is authored takes the next row's wrapper address and leaves its
    /// vault address empty. Only the wrapper probe sees it: the vault probe passes, the wrapper probe refuses, and the
    /// whole bundle reverts.
    function testWrapperFrontRunAfterAuthoringRevertsTheWholeBundle() external {
        executeNextBatch();
        SafeTx[] memory txs = sScript.callAuthorBundle();
        vm.prank(address(0xBEEF));
        IStoxWrappedTokenVaultBeaconSetDeployerV1(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1)
            .newStoxWrappedTokenVault(sScript.callToken(0).receiptVault);
        assertEq(sScript.callToken(20).receiptVault.code.length, 0, "next vault still empty");
        this.callAsSafe(txs[0]);
        assertEq(txs[1].to, sScript.callToken(20).wrappedTokenVault, "second entry probes the next wrapper");
        assertEq(txs[1].data, abi.encodeCall(ICloneableV2.initialize, ("")), "second entry is the probe");
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        this.callAsSafe(txs[1]);
        vm.expectRevert(gs013());
        this.executeAsSafe(txs);
    }

    /// @notice A front-run owned by anyone else reverts the bundle at the same probe, before the first `setAuthorizer`
    /// would refuse it as not the owner.
    function testFrontRunByAnotherOwnerRevertsTheWholeBundle() external {
        executeNextBatch();
        SafeTx[] memory txs = sScript.callAuthorBundle();
        createAs(address(0xBEEF), address(0xBEEF), rows()[20]);
        assertTheVaultProbeRefuses(txs);
        vm.expectRevert(gs013());
        this.executeAsSafe(txs);
        assertEq(sScript.callCreatedCount(), 21, "only the front-run's token");
    }

    /// @notice Why the probes open the bundle: without them, a copy of the next row owned by the Safe takes that row's
    /// address, the Safe wires it in place of its own token, and the rows shift by one with nothing reverting.
    function testWithoutItsProbesACopycatFrontRunShiftsTheRows() external {
        executeNextBatch();
        SafeTx[] memory txs = sScript.callAuthorBundle();
        SafeTx[] memory unprobed = new SafeTx[](txs.length - 2);
        for (uint256 i = 0; i < unprobed.length; i++) {
            unprobed[i] = txs[i + 2];
        }
        createAs(address(0xBEEF), safe(), rows()[20]);
        this.executeAsSafe(unprobed);
        vm.expectRevert(abi.encodeWithSelector(ZerogTokenMismatch.selector, rows()[21].underlying, "name"));
        sScript.callAssertPostState();
    }
}
