// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.1/src/Test.sol";

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155.sol";
import {CloneFactory} from "rain-factory-0.1.1/src/concrete/CloneFactory.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {
    OffchainAssetReceiptVault,
    OffchainAssetReceiptVaultConfigV2,
    DEPOSIT,
    WITHDRAW,
    CERTIFY
} from "rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config,
    CertificationExpired
} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {ReceiptVaultConfigV2} from "rain-vats-0.1.6/src/abstract/ReceiptVault.sol";
import {IAuthorizeV1} from "rain-vats-0.1.6/src/interface/IAuthorizeV1.sol";

import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {
    ST0xOrchestratorBeaconSetDeployer,
    ST0xOrchestratorBeaconSetDeployerConfig
} from "../../../src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {
    StoxOffchainAssetReceiptVaultBeaconSetDeployer
} from "../../../src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {ICorporateActionsV1} from "../../../src/interface/ICorporateActionsV1.sol";
import {SCHEDULE_CORPORATE_ACTION, STOCK_SPLIT_V1_TYPE_HASH} from "../../../src/lib/LibCorporateAction.sol";
import {LibStockSplit} from "../../../src/lib/LibStockSplit.sol";
import {LibProdDeployV4} from "../../../src/lib/LibProdDeployV4.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LibTestTofu} from "../../lib/LibTestTofu.sol";

/// @title ST0xOrchestratorRebaseIntegrationTest
/// @notice End-to-end integration tests for the orchestrator's core unit
/// assumption across stock-split corporate actions: the orchestrator's own
/// rebased `receipt.balanceOf` at each id is exactly what `vault.redeem`
/// accepts. Nothing vault-side is mocked — the suite deploys the real
/// `StoxReceiptVault` + `StoxReceipt` beacon set via the real
/// `StoxOffchainAssetReceiptVaultBeaconSetDeployer`, pairs the vault with a
/// real `StoxOffchainAssetReceiptVaultAuthorizerV1` clone, plants the real
/// corporate-actions facet at its deterministic address, and schedules /
/// completes splits through the vault's routed `scheduleCorporateAction`.
contract ST0xOrchestratorRebaseIntegrationTest is Test {
    /// @dev Mirrors `ST0xOrchestrator.MINT_BURN_ROLE`. Cached as a constant
    /// so `vm.prank` sequences don't waste the prank on an external view.
    bytes32 internal constant MINT_BURN_ROLE = keccak256("MINT_BURN");

    address internal constant ADMIN = address(uint160(uint256(keccak256("ADMIN"))));
    address internal constant OWNER = address(uint160(uint256(keccak256("OWNER"))));
    address internal constant MM = address(uint160(uint256(keccak256("MM"))));
    address internal constant RECIPIENT = address(uint160(uint256(keccak256("RECIPIENT"))));
    address internal constant SWEEP = address(uint160(uint256(keccak256("SWEEP"))));

    StoxReceiptVault internal vault;
    IERC1155 internal receipt;
    StoxOffchainAssetReceiptVaultAuthorizerV1 internal authorizer;
    ST0xOrchestrator internal orchestrator;

    function setUp() public {
        vm.warp(1000);

        // TOFU singleton first — stock-split multiplier validation reads the
        // vault's decimals through it at schedule time.
        LibTestTofu.deployTofu(vm);

        // Real receipt + vault implementations and their beacon-set deployer
        // at the deterministic Zoltu addresses.
        LibTestDeploy.deployOffchainAssetReceiptVaultBeaconSet(vm);

        // Real corporate-actions facet at the deterministic address the
        // vault's fallback delegatecalls into. Zoltu-deployed exactly as the
        // production `Deploy` script does, so `_SELF` matches the constant.
        address facet = LibRainDeploy.deployZoltu(type(StoxCorporateActionsFacet).creationCode);
        require(facet == LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_RAIN_VATS_0_1_6, "facet address mismatch");

        // A real vault + receipt beacon-proxy pair.
        vault = StoxReceiptVault(
            payable(address(
                    StoxOffchainAssetReceiptVaultBeaconSetDeployer(
                            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6
                        )
                        .newOffchainAssetReceiptVault(
                            OffchainAssetReceiptVaultConfigV2({
                                initialAdmin: ADMIN,
                                receiptVaultConfig: ReceiptVaultConfigV2({
                                    asset: address(0), name: "Test tStock", symbol: "tTEST", receipt: address(0)
                                })
                            })
                        )
                ))
        );
        receipt = IERC1155(address(vault.receipt()));

        // Real authoriser clone paired with the vault by its owner.
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizerImpl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        CloneFactory factory = new CloneFactory();
        authorizer = StoxOffchainAssetReceiptVaultAuthorizerV1(
            factory.clone(
                address(authorizerImpl), abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: ADMIN}))
            )
        );
        vm.prank(ADMIN);
        vault.setAuthorizer(IAuthorizeV1(address(authorizer)));

        // Orchestrator impl + beacon + proxy bound to the vault.
        ST0xOrchestrator impl = new ST0xOrchestrator();
        ST0xOrchestratorBeaconSetDeployer deployer = new ST0xOrchestratorBeaconSetDeployer(
            ST0xOrchestratorBeaconSetDeployerConfig({
                initialOwner: OWNER, initialOrchestratorImplementation: address(impl)
            })
        );
        orchestrator = ST0xOrchestrator(payable(deployer.deploy(vault, OWNER)));

        // Real role grants through the authoriser's admin — no storage pokes.
        vm.startPrank(ADMIN);
        authorizer.grantRole(DEPOSIT, address(orchestrator));
        authorizer.grantRole(WITHDRAW, address(orchestrator));
        authorizer.grantRole(CERTIFY, ADMIN);
        authorizer.grantRole(SCHEDULE_CORPORATE_ACTION, ADMIN);
        vm.stopPrank();

        // Certify far past every warp in the suite so ordinary share and
        // receipt transfers are unrestricted.
        vm.prank(ADMIN);
        vault.certify(1_000_000, false, "");

        // MM is the permissioned mint/burn caller on the orchestrator.
        vm.prank(OWNER);
        orchestrator.grantRole(MINT_BURN_ROLE, MM);
    }

    // ------------------------------------------------------------------ //
    //                              Helpers                               //
    // ------------------------------------------------------------------ //

    /// Schedule a stock split through the vault's routed corporate-actions
    /// facet and warp past its effective time so it completes.
    function scheduleAndCompleteSplit(Float multiplier) internal {
        uint64 effectiveTime = uint64(block.timestamp + 1000);
        vm.prank(ADMIN);
        ICorporateActionsV1(address(vault))
            .scheduleCorporateAction(
                STOCK_SPLIT_V1_TYPE_HASH, effectiveTime, LibStockSplit.encodeParametersV1(multiplier)
            );
        vm.warp(effectiveTime + 500);
    }

    /// Count `BurnShortfallMinted` logs emitted by the orchestrator and
    /// return the decoded fields of the last one seen.
    function shortfallLogs(Vm.Log[] memory logs)
        internal
        view
        returns (uint256 count, uint256 amount, uint256 receiptId)
    {
        bytes32 sig = ST0xOrchestrator.BurnShortfallMinted.selector;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(orchestrator) && logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                count++;
                (amount, receiptId) = abi.decode(logs[i].data, (uint256, uint256));
            }
        }
    }

    // ------------------------------------------------------------------ //
    //                          Forward split                             //
    // ------------------------------------------------------------------ //

    /// A 3:1 forward split rebases both the recipient's share balance and
    /// the orchestrator's held receipt in lockstep, and burning the FULL
    /// rebased balance consumes the receipt exactly — the walk needs no
    /// shortfall mint because `receipt.balanceOf` (rebased) is exactly what
    /// `vault.redeem` accepts post-split.
    function testOrchestratorBurnAfterForwardSplitConsumesRebasedReceiptExactly() external {
        uint256 minted = 90e18;
        vm.prank(MM);
        orchestrator.mint(RECIPIENT, minted);
        uint256 mintedId = vault.highwaterId();
        assertEq(mintedId, 1, "first mint on a fresh vault lands at id 1");
        assertEq(orchestrator.nextBurnReceiptId(), mintedId, "pointer seeded at the first id the clone can mint");

        scheduleAndCompleteSplit(LibDecimalFloat.packLossless(3, 0));

        // Share side and receipt side rebase in lockstep: 90e18 * 3.
        assertEq(vault.balanceOf(RECIPIENT), 270e18, "recipient share balance rebased 3x");
        assertEq(receipt.balanceOf(address(orchestrator), mintedId), 270e18, "orchestrator receipt rebased 3x");

        vm.prank(RECIPIENT);
        IERC20(address(vault)).approve(address(orchestrator), 270e18);

        vm.recordLogs();
        vm.prank(MM);
        orchestrator.burn(RECIPIENT, 270e18);

        assertEq(vault.balanceOf(RECIPIENT), 0, "recipient drained");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), 0, "no shares stranded on orchestrator");
        assertEq(receipt.balanceOf(address(orchestrator), mintedId), 0, "receipt fully consumed");
        assertEq(orchestrator.nextBurnReceiptId(), mintedId + 1, "pointer advanced one past the consumed id");
        assertEq(vault.totalSupply(), 0, "supply fully unwound");

        // The rebased receipt exactly covered the rebased burn: no
        // shortfall mint anywhere in the call.
        (uint256 count,,) = shortfallLogs(vm.getRecordedLogs());
        assertEq(count, 0, "no BurnShortfallMinted for an exactly-covered burn");
    }

    // ------------------------------------------------------------------ //
    //                         Fractional split                           //
    // ------------------------------------------------------------------ //

    /// A 1:3 reverse split truncates the receipt side per-id but the share
    /// side per-account, so with two small receipts the orchestrator's held
    /// receipt units total less than the recipient's rebased share balance.
    /// Burning the FULL rebased balance still completes: the walk consumes
    /// both receipts and covers the truncation dust with a single
    /// mint-on-demand (`BurnShortfallMinted`), stranding exactly the gap on
    /// the orchestrator.
    function testOrchestratorBurnAfterFractionalSplitCoversTruncationDust() external {
        // Two separate small receipts, each of which truncates on a 1/3
        // multiplier: trunc(5/3) == 1 per id, but trunc(10/3) == 3 for the
        // account-level share balance — a 1-unit gap.
        vm.prank(MM);
        orchestrator.mint(RECIPIENT, 5);
        vm.prank(MM);
        orchestrator.mint(RECIPIENT, 5);
        uint256 idA = 1;
        uint256 idB = 2;
        assertEq(vault.highwaterId(), idB, "two receipts minted");

        scheduleAndCompleteSplit(
            LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(3, 0))
        );

        uint256 burnAmount = vault.balanceOf(RECIPIENT);
        uint256 receiptTotal =
            receipt.balanceOf(address(orchestrator), idA) + receipt.balanceOf(address(orchestrator), idB);
        // Pin the concrete truncation shape so the scenario stays meaningful:
        // per-account share truncation keeps more than the per-id receipt
        // truncations do.
        assertEq(burnAmount, 3, "account-level share truncation: trunc(10 * 1/3) == 3");
        assertEq(receiptTotal, 2, "per-id receipt truncation: trunc(5 * 1/3) * 2 == 2");
        uint256 gap = burnAmount - receiptTotal;
        assertGt(gap, 0, "scenario must produce truncation dust");

        vm.prank(RECIPIENT);
        IERC20(address(vault)).approve(address(orchestrator), burnAmount);

        uint256 supplyBefore = vault.totalSupply();

        vm.recordLogs();
        vm.prank(MM);
        orchestrator.burn(RECIPIENT, burnAmount);

        // Burn completed: recipient drained, both held receipts consumed.
        assertEq(vault.balanceOf(RECIPIENT), 0, "recipient drained");
        assertEq(receipt.balanceOf(address(orchestrator), idA), 0, "receipt idA consumed");
        assertEq(receipt.balanceOf(address(orchestrator), idB), 0, "receipt idB consumed");

        // The dust was covered by exactly one mint-on-demand at a fresh id.
        uint256 onDemandId = idB + 1;
        (uint256 count, uint256 shortfallAmount, uint256 shortfallId) = shortfallLogs(vm.getRecordedLogs());
        assertEq(count, 1, "exactly one BurnShortfallMinted");
        assertEq(shortfallAmount, gap, "shortfall equals the truncation gap");
        assertEq(shortfallId, onDemandId, "shortfall receipt minted at highwater + 1");
        assertEq(vault.highwaterId(), onDemandId, "highwater advanced by the on-demand mint");
        assertEq(receipt.balanceOf(address(orchestrator), onDemandId), 0, "on-demand receipt immediately consumed");
        assertEq(orchestrator.nextBurnReceiptId(), onDemandId + 1, "pointer one past the on-demand id");

        // The mint-on-demand cycle nets to zero supply, so the burn removed
        // only what the receipts backed; the stranded shares on the
        // orchestrator equal the truncation gap, awaiting the admin sweep.
        assertEq(
            IERC20(address(vault)).balanceOf(address(orchestrator)), gap, "stranded shares equal the truncation gap"
        );
        assertEq(vault.totalSupply(), supplyBefore - receiptTotal, "supply shrank only by the receipt-backed portion");

        // The documented `withdrawShares` escape hatch completes the cycle:
        // the admin sweeps the stranded dust out for real, the swept balance
        // arrives at the destination, and the orchestrator zeroes out.
        vm.prank(OWNER);
        orchestrator.withdrawShares(gap, SWEEP);
        assertEq(IERC20(address(vault)).balanceOf(SWEEP), gap, "swept dust arrived at the destination");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), 0, "orchestrator fully swept");
    }

    /// After a fractional split, an external mint of an amount that doesn't
    /// divide evenly under the multiplier still delivers exactly `x` to the
    /// recipient, with nothing stranded on the orchestrator: `vault.mint`
    /// credits the orchestrator `x` in rebased units and the ERC-20 forward
    /// moves exactly `x` on.
    function testOrchestratorExternalMintAfterFractionalSplitDeliversExactAmount() external {
        // Seed some pre-split state so the split rebases live balances.
        vm.prank(MM);
        orchestrator.mint(RECIPIENT, 5);

        scheduleAndCompleteSplit(
            LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(3, 0))
        );

        // 7 is truncation-prone under the 1/3 multiplier — it has no exact
        // pre-rebase preimage in whole units.
        uint256 amount = 7;
        uint256 preRecipient = vault.balanceOf(RECIPIENT);

        vm.prank(MM);
        orchestrator.mint(RECIPIENT, amount);

        assertEq(vault.balanceOf(RECIPIENT) - preRecipient, amount, "recipient gains exactly the minted amount");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), 0, "nothing stranded on the orchestrator");
    }

    // ------------------------------------------------------------------ //
    //                       Escape-hatch round-trips                     //
    // ------------------------------------------------------------------ //

    /// `withdrawReceipt` pulls a live receipt out to an EOA for real: the
    /// receipt balances move on the real receipt contract, and — because the
    /// backing left the orchestrator — a subsequent burn covering that id's
    /// range must take the mint-on-demand shortfall path.
    function testOrchestratorWithdrawReceiptRoundTrip() external {
        uint256 minted = 6e18;
        vm.prank(MM);
        orchestrator.mint(RECIPIENT, minted);
        uint256 mintedId = vault.highwaterId();
        assertEq(receipt.balanceOf(address(orchestrator), mintedId), minted, "orchestrator holds the fresh receipt");

        vm.prank(OWNER);
        orchestrator.withdrawReceipt(mintedId, minted, SWEEP);
        assertEq(receipt.balanceOf(address(orchestrator), mintedId), 0, "receipt left the orchestrator");
        assertEq(receipt.balanceOf(SWEEP, mintedId), minted, "receipt arrived at the EOA");

        // With the receipt gone the walk finds nothing at mintedId and
        // overruns the cap: the whole burn is covered by mint-on-demand.
        vm.prank(RECIPIENT);
        IERC20(address(vault)).approve(address(orchestrator), minted);

        uint256 supplyBefore = vault.totalSupply();
        vm.recordLogs();
        vm.prank(MM);
        orchestrator.burn(RECIPIENT, minted);

        uint256 onDemandId = mintedId + 1;
        (uint256 count, uint256 shortfallAmount, uint256 shortfallId) = shortfallLogs(vm.getRecordedLogs());
        assertEq(count, 1, "exactly one BurnShortfallMinted");
        assertEq(shortfallAmount, minted, "the whole burn is shortfall since the backing left");
        assertEq(shortfallId, onDemandId, "shortfall receipt minted at highwater + 1");
        assertEq(vault.balanceOf(RECIPIENT), 0, "recipient drained");
        assertEq(vault.totalSupply(), supplyBefore, "mint-on-demand cycle nets zero supply");
        assertEq(
            IERC20(address(vault)).balanceOf(address(orchestrator)), minted, "pulled shares stranded for the sweep"
        );
        assertEq(orchestrator.nextBurnReceiptId(), onDemandId + 1, "pointer one past the on-demand id");
    }

    // ------------------------------------------------------------------ //
    //                        Certification lapse                         //
    // ------------------------------------------------------------------ //

    /// Once the vault's certification lapses, the orchestrator's self-flows
    /// keep working — the authoriser exempts the mint leg (0 → orchestrator)
    /// for `DEPOSIT` holders and the burn leg (orchestrator → 0) for
    /// `WITHDRAW` holders — but any flow touching an external account
    /// reverts `CertificationExpired` on the ordinary ERC-20 transfer leg.
    function testOrchestratorCertificationLapseSelfFlowsOnly() external {
        uint256 minted = 10e18;
        vm.prank(MM);
        orchestrator.mint(RECIPIENT, minted);

        // setUp certifies until t = 1_000_000; expiry is strict `>`.
        vm.warp(1_000_001);
        assertTrue(vault.isCertificationExpired(), "certification must have lapsed");

        // (a) Self-mint still works: no external transfer follows the
        // exempt mint leg.
        uint256 selfMint = 4e18;
        vm.prank(MM);
        orchestrator.mint(address(orchestrator), selfMint);
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), selfMint, "self-mint credited");

        // (b) External mint reverts on the ERC-20 forward leg.
        vm.prank(MM);
        vm.expectRevert(abi.encodeWithSelector(CertificationExpired.selector, address(orchestrator), RECIPIENT));
        orchestrator.mint(RECIPIENT, 1e18);

        // (c) Self-burn still works and reduces supply: no pull leg, and
        // the redeem consumes the orchestrator's held receipts.
        uint256 supplyBefore = vault.totalSupply();
        uint256 burnAmount = 3e18;
        vm.prank(MM);
        orchestrator.burn(address(orchestrator), burnAmount);
        assertEq(vault.totalSupply(), supplyBefore - burnAmount, "self-burn reduced supply");
        assertEq(
            IERC20(address(vault)).balanceOf(address(orchestrator)),
            selfMint - burnAmount,
            "self balance partially consumed"
        );

        // (d) External burn reverts on the pull leg. The approve itself is
        // fine — allowances aren't transfers.
        vm.prank(RECIPIENT);
        IERC20(address(vault)).approve(address(orchestrator), minted);
        vm.prank(MM);
        vm.expectRevert(abi.encodeWithSelector(CertificationExpired.selector, RECIPIENT, address(orchestrator)));
        orchestrator.burn(RECIPIENT, minted);
    }
}
