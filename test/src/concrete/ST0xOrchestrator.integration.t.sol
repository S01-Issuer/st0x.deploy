// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.1/src/Test.sol";

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.6.1/proxy/beacon/BeaconProxy.sol";
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
import {IAuthorizeV1, Unauthorized} from "rain-vats-0.1.6/src/interface/IAuthorizeV1.sol";

import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {IMintRecipient} from "../../../src/interface/IMintRecipient.sol";
import {IST0xVaultBeaconSet} from "../../../src/interface/IST0xVaultBeaconSet.sol";
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

/// @title ST0xOrchestratorIntegration
/// @notice Real-deployment integration tests for the SINGLETON
/// `ST0xOrchestrator`. Nothing vault-side is mocked. The suite builds the
/// full local V4 substrate — TOFU singleton, the real `StoxReceipt` +
/// `StoxReceiptVault` implementations and their beacon-set deployer
/// Zoltu-deployed to the deterministic addresses `LibProdDeployV4` pins, a
/// real vault+receipt beacon-proxy pair, a real corporate-actions facet, and
/// a real authoriser clone — so the orchestrator's hardcoded vault-version
/// guard (`onlyExpectedVaultLogic`) reads the genuine production beacons and
/// passes. Every mint/burn then exercises the real
/// mint/redeem/receipt/rebase machinery end-to-end.
contract ST0xOrchestratorIntegration is Test {
    address internal constant ADMIN = address(uint160(uint256(keccak256("ADMIN"))));
    address internal constant OWNER = address(uint160(uint256(keccak256("OWNER"))));
    address internal constant MM = address(uint160(uint256(keccak256("MM"))));
    address internal constant SWEEP = address(uint160(uint256(keccak256("SWEEP"))));

    /// Beacon owner for the OARV beacon set — the address the beacon-set
    /// deployer hands ownership to at construction. Needed to upgrade the
    /// vault beacon out from under the guard (test 7).
    address internal constant BEACON_OWNER = LibProdDeployV4.BEACON_INITIAL_OWNER;

    StoxReceiptVault internal vault;
    IERC1155 internal receipt;
    StoxOffchainAssetReceiptVaultAuthorizerV1 internal authorizer;
    ST0xOrchestrator internal impl;
    ST0xOrchestrator internal orchestrator;

    function setUp() public {
        vm.warp(1000);

        // TOFU singleton first — stock-split multiplier validation reads the
        // vault's decimals through it at schedule time.
        LibTestTofu.deployTofu(vm);

        // Real receipt + vault implementations and their beacon-set deployer
        // at the deterministic Zoltu addresses the guard reads.
        LibTestDeploy.deployOffchainAssetReceiptVaultBeaconSet(vm);

        // Real corporate-actions facet at the deterministic address the
        // vault's fallback delegatecalls into.
        address facet = LibRainDeploy.deployZoltu(type(StoxCorporateActionsFacet).creationCode);
        require(facet == LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_RAIN_VATS_0_1_6, "facet address mismatch");

        // A real vault + receipt beacon-proxy pair via the deterministic
        // deployer the guard version-locks against.
        vault = _newVault();
        receipt = IERC1155(address(vault.receipt()));

        // Real authoriser clone paired with the vault by its owner.
        authorizer = _newAuthorizer();
        vm.prank(ADMIN);
        vault.setAuthorizer(IAuthorizeV1(address(authorizer)));

        // Orchestrator impl behind a real UpgradeableBeacon + BeaconProxy,
        // initialised with OWNER as DEFAULT_ADMIN_ROLE.
        impl = new ST0xOrchestrator();
        orchestrator = _deployOrchestrator(OWNER);

        // Grant the orchestrator DEPOSIT + WITHDRAW on the vault through the
        // authoriser's admin — real grants, no storage pokes.
        vm.startPrank(ADMIN);
        authorizer.grantRole(DEPOSIT, address(orchestrator));
        authorizer.grantRole(WITHDRAW, address(orchestrator));
        authorizer.grantRole(CERTIFY, ADMIN);
        authorizer.grantRole(SCHEDULE_CORPORATE_ACTION, ADMIN);
        vm.stopPrank();

        // Certify far past every warp in the ordinary flows so share/receipt
        // transfers are unrestricted (the lapse test re-certifies short).
        vm.prank(ADMIN);
        vault.certify(1_000_000, false, "");

        // MM is the permissioned mint/burn caller on the orchestrator.
        vm.startPrank(OWNER);
        orchestrator.grantRole(orchestrator.MINT_ROLE(), MM);
        orchestrator.grantRole(orchestrator.BURN_ROLE(), MM);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ //
    //                              Helpers                               //
    // ------------------------------------------------------------------ //

    function _newVault() internal returns (StoxReceiptVault) {
        return StoxReceiptVault(
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
    }

    function _newAuthorizer() internal returns (StoxOffchainAssetReceiptVaultAuthorizerV1) {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizerImpl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        CloneFactory factory = new CloneFactory();
        return StoxOffchainAssetReceiptVaultAuthorizerV1(
            factory.clone(
                address(authorizerImpl), abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: ADMIN}))
            )
        );
    }

    function _deployOrchestrator(address owner) internal returns (ST0xOrchestrator) {
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        bytes memory initData = abi.encodeCall(ST0xOrchestrator.initialize, (owner));
        BeaconProxy proxy = new BeaconProxy(address(beacon), initData);
        return ST0xOrchestrator(payable(address(proxy)));
    }

    /// Encode `mint` data: `abi.encode(signature, nonce, receiptInformation)`.
    function _mintData(bytes memory sig, bytes32 nonce, bytes memory info) internal pure returns (bytes memory) {
        return abi.encode(sig, nonce, info);
    }

    /// Sign the recipient's mint authorisation for an EOA recipient and encode
    /// the resulting `mint` data blob.
    function _signedMintData(address token, address to, uint256 amount, bytes32 nonce, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = orchestrator.mintAuthDigest(token, to, amount, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return _mintData(abi.encodePacked(r, s, v), nonce, "");
    }

    /// Schedule a stock split through the vault's routed corporate-actions
    /// facet and warp past its effective time so it completes.
    function _scheduleAndCompleteSplit(Float multiplier) internal {
        uint64 effectiveTime = uint64(block.timestamp + 1000);
        vm.prank(ADMIN);
        ICorporateActionsV1(address(vault))
            .scheduleCorporateAction(
                STOCK_SPLIT_V1_TYPE_HASH, effectiveTime, LibStockSplit.encodeParametersV1(multiplier)
            );
        vm.warp(effectiveTime + 500);
    }

    /// Count `BurnShortfallMinted` logs emitted by the orchestrator and return
    /// the decoded fields of the last one seen.
    function _shortfallLogs(Vm.Log[] memory logs)
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
    // 1. Guard passes against the real V4 beacons                        //
    // ------------------------------------------------------------------ //

    /// The orchestrator's hardcoded guard reads the REAL deterministic OARV
    /// beacon-set deployer and its two beacons, and finds them pointing at the
    /// real V4 impls — so `vaultLogicIsExpected()` is true and a mint against
    /// a real vault completes.
    function testGuardPassesAgainstRealV4Beacons() external {
        // The guard reads the genuine production deployer + beacons.
        assertTrue(orchestrator.vaultLogicIsExpected(), "guard must pass against the real V4 beacons");

        // Cross-check the beacons the guard reads really are the V4 impls.
        IST0xVaultBeaconSet beaconSet =
            IST0xVaultBeaconSet(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6);
        assertEq(
            beaconSet.iOffchainAssetReceiptVaultBeacon().implementation(),
            LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6,
            "vault beacon points at V4 vault impl"
        );
        assertEq(
            beaconSet.iReceiptBeacon().implementation(),
            LibProdDeployV4.STOX_RECEIPT_RAIN_VATS_0_1_6,
            "receipt beacon points at V4 receipt impl"
        );

        // And a mint against the real vault goes through with the guard live.
        (address eoa, uint256 pk) = makeAddrAndKey("guard-recipient");
        uint256 amount = 7e18;
        bytes32 nonce = keccak256("guard");
        bytes memory data = _signedMintData(address(vault), eoa, amount, nonce, pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, amount, data);
        assertEq(vault.balanceOf(eoa), amount, "mint delivered against the real vault");
    }

    // ------------------------------------------------------------------ //
    // 2. Mint with ECDSA auth delivers shares                            //
    // ------------------------------------------------------------------ //

    /// EOA recipient authorises with an ECDSA signature over the EIP-712
    /// digest. The receipt is minted to and kept by the orchestrator at
    /// highwater+1; the shares are forwarded to the recipient in real rebased
    /// units; the orchestrator's own share balance nets to zero.
    function testMintWithECDSAAuthDeliversShares() external {
        (address eoa, uint256 pk) = makeAddrAndKey("ecdsa-recipient");
        uint256 amount = 123e18;
        bytes32 nonce = keccak256("ecdsa");

        assertEq(vault.highwaterId(), 0, "fresh vault has no receipts");

        bytes memory data = _signedMintData(address(vault), eoa, amount, nonce, pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, amount, data);

        uint256 mintedId = vault.highwaterId();
        assertEq(mintedId, 1, "first mint lands at id 1");
        assertEq(vault.balanceOf(eoa), amount, "recipient received the rebased shares");
        assertEq(receipt.balanceOf(address(orchestrator), mintedId), amount, "orchestrator holds the receipt");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), 0, "orchestrator holds no shares");
        assertEq(orchestrator.nextBurnReceiptId(address(vault)), mintedId, "pointer seeded at the first mintable id");
    }

    // ------------------------------------------------------------------ //
    // 3. Mint with callback recipient                                    //
    // ------------------------------------------------------------------ //

    /// A contract recipient with no key authorises via the `IMintRecipient`
    /// callback (empty signature). The mint completes and delivers shares to
    /// the contract.
    function testMintWithCallbackRecipient() external {
        AcceptingMintRecipient recipient = new AcceptingMintRecipient();
        uint256 amount = 42e18;
        bytes32 nonce = keccak256("callback");

        vm.prank(MM);
        orchestrator.mint(address(vault), address(recipient), amount, _mintData("", nonce, ""));

        assertEq(vault.balanceOf(address(recipient)), amount, "callback recipient received the shares");
        assertEq(receipt.balanceOf(address(orchestrator), vault.highwaterId()), amount, "orchestrator holds receipt");
    }

    // ------------------------------------------------------------------ //
    // 4. Burn happy path + pointer                                       //
    // ------------------------------------------------------------------ //

    /// MM mints to an EOA, the EOA approves the orchestrator, MM burns the
    /// full amount. The recipient is drained, the receipt consumed, the
    /// pointer advances one past the consumed id, and no shortfall is minted.
    function testBurnHappyPathAndPointer() external {
        (address eoa, uint256 pk) = makeAddrAndKey("burn-recipient");
        uint256 amount = 55e18;
        bytes32 nonce = keccak256("burn");

        bytes memory data = _signedMintData(address(vault), eoa, amount, nonce, pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, amount, data);
        uint256 mintedId = vault.highwaterId();

        vm.prank(eoa);
        IERC20(address(vault)).approve(address(orchestrator), amount);

        vm.recordLogs();
        vm.prank(MM);
        orchestrator.burn(address(vault), eoa, amount, "");

        assertEq(vault.balanceOf(eoa), 0, "recipient drained");
        assertEq(receipt.balanceOf(address(orchestrator), mintedId), 0, "receipt consumed");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), 0, "no shares stranded");
        assertEq(orchestrator.nextBurnReceiptId(address(vault)), mintedId + 1, "pointer advanced one past consumed id");
        assertEq(vault.totalSupply(), 0, "supply fully unwound");

        (uint256 count,,) = _shortfallLogs(vm.getRecordedLogs());
        assertEq(count, 0, "no BurnShortfallMinted on an exactly-covered burn");
    }

    // ------------------------------------------------------------------ //
    // 5. Burn after forward split consumes rebased receipt exactly       //
    // ------------------------------------------------------------------ //

    /// A 3:1 forward split rebases the recipient's shares and the
    /// orchestrator's held receipt in lockstep. Burning the full rebased
    /// balance drains both exactly with no shortfall mint.
    function testBurnAfterForwardSplitConsumesRebasedReceiptExactly() external {
        (address eoa, uint256 pk) = makeAddrAndKey("split-recipient");
        uint256 minted = 90e18;
        bytes32 nonce = keccak256("fwd-split");

        bytes memory data = _signedMintData(address(vault), eoa, minted, nonce, pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, minted, data);
        uint256 mintedId = vault.highwaterId();
        assertEq(mintedId, 1, "first mint on a fresh vault lands at id 1");

        _scheduleAndCompleteSplit(LibDecimalFloat.packLossless(3, 0));

        assertEq(vault.balanceOf(eoa), 270e18, "recipient share balance rebased 3x");
        assertEq(receipt.balanceOf(address(orchestrator), mintedId), 270e18, "orchestrator receipt rebased 3x");

        vm.prank(eoa);
        IERC20(address(vault)).approve(address(orchestrator), 270e18);

        vm.recordLogs();
        vm.prank(MM);
        orchestrator.burn(address(vault), eoa, 270e18, "");

        assertEq(vault.balanceOf(eoa), 0, "recipient drained");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), 0, "no shares stranded");
        assertEq(receipt.balanceOf(address(orchestrator), mintedId), 0, "receipt fully consumed");
        assertEq(orchestrator.nextBurnReceiptId(address(vault)), mintedId + 1, "pointer advanced one past consumed id");
        assertEq(vault.totalSupply(), 0, "supply fully unwound");

        (uint256 count,,) = _shortfallLogs(vm.getRecordedLogs());
        assertEq(count, 0, "no BurnShortfallMinted for an exactly-covered burn");
    }

    // ------------------------------------------------------------------ //
    // 6. Burn after fractional split covers truncation dust              //
    // ------------------------------------------------------------------ //

    /// A 1:3 reverse split truncates the receipt side per-id but the share
    /// side per-account, leaving the held receipts short of the rebased share
    /// balance by one unit. Burning the full balance covers the gap with a
    /// single mint-on-demand (`BurnShortfallMinted`), stranding exactly the
    /// gap on the orchestrator; the `EMERGENCY_ROLE` `withdrawShares` sweeps
    /// it to zero.
    function testBurnAfterFractionalSplitCoversTruncationDust() external {
        (address eoa, uint256 pkA) = makeAddrAndKey("frac-recipient");

        // Two separate small receipts, each of which truncates on a 1/3
        // multiplier: trunc(5/3) == 1 per id, but trunc(10/3) == 3 for the
        // account-level share balance — a 1-unit gap.
        bytes memory dataA = _signedMintData(address(vault), eoa, 5, keccak256("fa"), pkA);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, 5, dataA);
        bytes memory dataB = _signedMintData(address(vault), eoa, 5, keccak256("fb"), pkA);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, 5, dataB);
        uint256 idA = 1;
        uint256 idB = 2;
        assertEq(vault.highwaterId(), idB, "two receipts minted");

        _scheduleAndCompleteSplit(
            LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(3, 0))
        );

        uint256 burnAmount = vault.balanceOf(eoa);
        uint256 receiptTotal =
            receipt.balanceOf(address(orchestrator), idA) + receipt.balanceOf(address(orchestrator), idB);
        assertEq(burnAmount, 3, "account-level share truncation: trunc(10 * 1/3) == 3");
        assertEq(receiptTotal, 2, "per-id receipt truncation: trunc(5 * 1/3) * 2 == 2");
        uint256 gap = burnAmount - receiptTotal;
        assertGt(gap, 0, "scenario must produce truncation dust");

        vm.prank(eoa);
        IERC20(address(vault)).approve(address(orchestrator), burnAmount);

        vm.recordLogs();
        vm.prank(MM);
        orchestrator.burn(address(vault), eoa, burnAmount, "");

        assertEq(vault.balanceOf(eoa), 0, "recipient drained");
        assertEq(receipt.balanceOf(address(orchestrator), idA), 0, "receipt idA consumed");
        assertEq(receipt.balanceOf(address(orchestrator), idB), 0, "receipt idB consumed");

        uint256 onDemandId = idB + 1;
        (uint256 count, uint256 shortfallAmount, uint256 shortfallId) = _shortfallLogs(vm.getRecordedLogs());
        assertEq(count, 1, "exactly one BurnShortfallMinted");
        assertEq(shortfallAmount, gap, "shortfall equals the truncation gap");
        assertEq(shortfallId, onDemandId, "shortfall receipt minted at highwater + 1");
        assertEq(orchestrator.nextBurnReceiptId(address(vault)), onDemandId + 1, "pointer one past the on-demand id");

        // Stranded shares equal the truncation gap, awaiting the sweep.
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), gap, "stranded shares equal the gap");

        // EMERGENCY_ROLE sweep completes the cycle.
        bytes32 emergencyRole = orchestrator.EMERGENCY_ROLE();
        vm.prank(OWNER);
        orchestrator.grantRole(emergencyRole, ADMIN);
        vm.prank(ADMIN);
        orchestrator.withdrawShares(address(vault), gap, SWEEP);
        assertEq(IERC20(address(vault)).balanceOf(SWEEP), gap, "swept dust arrived at the destination");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), 0, "orchestrator fully swept");
    }

    // ------------------------------------------------------------------ //
    // 7. Guard halts after a vault-beacon upgrade                        //
    // ------------------------------------------------------------------ //

    /// Upgrading the OARV vault beacon to a different implementation, as the
    /// beacon owner, breaks the orchestrator's version lock: `vaultLogicIsExpected`
    /// flips false and both `mint` and `burn` revert `VaultLogicMismatch`.
    function testGuardHaltsAfterVaultBeaconUpgrade() external {
        assertTrue(orchestrator.vaultLogicIsExpected(), "guard passes before the upgrade");

        IBeacon vaultBeacon = IST0xVaultBeaconSet(
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6
            ).iOffchainAssetReceiptVaultBeacon();

        // A fresh, valid impl address (any contract with code works as an
        // UpgradeableBeacon target) that is NOT the pinned V4 vault impl.
        address newImpl = address(new ST0xOrchestrator());
        vm.prank(BEACON_OWNER);
        UpgradeableBeacon(address(vaultBeacon)).upgradeTo(newImpl);

        assertFalse(orchestrator.vaultLogicIsExpected(), "guard halts after the vault beacon upgrade");

        (address eoa, uint256 pk) = makeAddrAndKey("halt-recipient");
        bytes memory data = _signedMintData(address(vault), eoa, 1e18, keccak256("halt"), pk);
        vm.prank(MM);
        vm.expectRevert(
            abi.encodeWithSelector(
                ST0xOrchestrator.VaultLogicMismatch.selector,
                LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6,
                newImpl
            )
        );
        orchestrator.mint(address(vault), eoa, 1e18, data);

        vm.prank(MM);
        vm.expectRevert(
            abi.encodeWithSelector(
                ST0xOrchestrator.VaultLogicMismatch.selector,
                LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6,
                newImpl
            )
        );
        orchestrator.burn(address(vault), eoa, 1e18, "");
    }

    // ------------------------------------------------------------------ //
    // 8. Certification lapse — self-flows only                           //
    // ------------------------------------------------------------------ //

    /// Once certification lapses, external mints revert on the ERC-20 forward
    /// leg (`CertificationExpired`), while a self-burn — orchestrator burning
    /// its own held shares — still works because the authoriser exempts the
    /// (orchestrator -> 0) redeem leg for `WITHDRAW` holders and there is no
    /// external pull.
    function testCertificationLapseSelfFlowsOnly() external {
        (address eoa, uint256 pk) = makeAddrAndKey("cert-recipient");

        // Pre-lapse external mint to an EOA succeeds.
        uint256 minted = 10e18;
        bytes memory data0 = _signedMintData(address(vault), eoa, minted, keccak256("c0"), pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, minted, data0);

        // Seed the orchestrator with self-held shares so the self-burn has
        // something to consume during the lapse. The orchestrator does not
        // implement `IMintRecipient`, so it can't authorise a mint to itself
        // directly; instead mint (pre-lapse) to a callback recipient and have
        // it forward the shares onto the orchestrator.
        SelfHoldingRecipient self = new SelfHoldingRecipient();
        uint256 selfMint = 4e18;
        vm.prank(MM);
        orchestrator.mint(address(vault), address(self), selfMint, _mintData("", keccak256("c1"), ""));
        // Move those shares onto the orchestrator for a genuine self-burn.
        vm.prank(address(self));
        IERC20(address(vault)).transfer(address(orchestrator), selfMint);
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), selfMint, "orchestrator holds self shares");

        // Lapse certification. setUp certified until t = 1_000_000; expiry is
        // strict `>`.
        vm.warp(1_000_001);
        assertTrue(vault.isCertificationExpired(), "certification must have lapsed");

        // External mint reverts on the ERC-20 forward leg.
        bytes memory extData = _signedMintData(address(vault), eoa, 1e18, keccak256("c2"), pk);
        vm.prank(MM);
        vm.expectRevert(abi.encodeWithSelector(CertificationExpired.selector, address(orchestrator), eoa));
        orchestrator.mint(address(vault), eoa, 1e18, extData);

        // Self-burn still works: no external pull, and the redeem leg
        // (orchestrator -> 0) is exempt for WITHDRAW holders.
        uint256 supplyBefore = vault.totalSupply();
        uint256 burnAmount = 3e18;
        vm.prank(MM);
        orchestrator.burn(address(vault), address(orchestrator), burnAmount, "");
        assertEq(vault.totalSupply(), supplyBefore - burnAmount, "self-burn reduced supply");
        assertEq(
            IERC20(address(vault)).balanceOf(address(orchestrator)),
            selfMint - burnAmount,
            "self balance partially consumed"
        );
    }

    // ------------------------------------------------------------------ //
    // 9. Mint reverts without the vault roles                            //
    // ------------------------------------------------------------------ //

    /// A fresh orchestrator with `MINT_ROLE` granted but WITHOUT the vault's
    /// `DEPOSIT` grant on the authoriser cannot mint: the vault's `mint` leg
    /// reverts the rain-vats `Unauthorized`.
    function testMintRevertsWithoutVaultRoles() external {
        // Fresh orchestrator, never granted DEPOSIT/WITHDRAW on the authoriser.
        ST0xOrchestrator fresh = _deployOrchestrator(OWNER);
        bytes32 mintRole = fresh.MINT_ROLE();
        vm.prank(OWNER);
        fresh.grantRole(mintRole, MM);

        (address eoa, uint256 pk) = makeAddrAndKey("norole-recipient");
        uint256 amount = 1e18;
        bytes32 nonce = keccak256("norole");
        bytes32 digest = fresh.mintAuthDigest(address(vault), eoa, amount, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        bytes memory data = _mintData(abi.encodePacked(r, s, v), nonce, "");

        vm.prank(MM);
        vm.expectPartialRevert(Unauthorized.selector);
        fresh.mint(address(vault), eoa, amount, data);
    }
}

/// @dev Contract recipient that authorises any mint via the `IMintRecipient`
/// callback (accepts unconditionally). Holds the shares it is minted.
contract AcceptingMintRecipient is IMintRecipient {
    function authorizeMint(bytes32) external pure returns (bytes4) {
        return IMintRecipient.authorizeMint.selector;
    }
}

/// @dev Callback recipient used to seed the orchestrator with self-held
/// shares: it accepts the mint, then the test forwards the received shares
/// onto the orchestrator for a genuine self-burn.
contract SelfHoldingRecipient is IMintRecipient {
    function authorizeMint(bytes32) external pure returns (bytes4) {
        return IMintRecipient.authorizeMint.selector;
    }
}
