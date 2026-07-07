// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {IERC1155} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.6.1/proxy/beacon/BeaconProxy.sol";
import {CloneFactory} from "rain-factory-0.1.1/src/concrete/CloneFactory.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {Float} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {
    OffchainAssetReceiptVaultConfigV2,
    DEPOSIT,
    WITHDRAW,
    CERTIFY
} from "rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {ReceiptVaultConfigV2} from "rain-vats-0.1.6/src/abstract/ReceiptVault.sol";
import {IAuthorizeV1} from "rain-vats-0.1.6/src/interface/IAuthorizeV1.sol";

import {ST0xOrchestrator} from "../../../../src/concrete/ST0xOrchestrator.sol";
import {IMintRecipient} from "../../../../src/interface/IMintRecipient.sol";
import {MintAuthV1, Digest} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {StoxCorporateActionsFacet} from "../../../../src/concrete/StoxCorporateActionsFacet.sol";
import {StoxReceiptVault} from "../../../../src/concrete/StoxReceiptVault.sol";
import {
    StoxOffchainAssetReceiptVaultBeaconSetDeployer
} from "../../../../src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {ICorporateActionsV1} from "../../../../src/interface/ICorporateActionsV1.sol";
import {SCHEDULE_CORPORATE_ACTION, STOCK_SPLIT_V1_TYPE_HASH} from "../../../../src/lib/LibCorporateAction.sol";
import {LibStockSplit} from "../../../../src/lib/LibStockSplit.sol";
import {LibProdDeployV4} from "../../../../src/lib/LibProdDeployV4.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";
import {LibTestTofu} from "../../../lib/LibTestTofu.sol";

/// @title OrchestratorIntegrationTest
/// @notice Shared base for the real-deployment integration tests of the
/// SINGLETON `ST0xOrchestrator` — one workflow per concrete file in this
/// folder. Nothing vault-side is mocked. The setUp builds the full local V4
/// substrate — TOFU singleton, the real `StoxReceipt` + `StoxReceiptVault`
/// implementations and their beacon-set deployer Zoltu-deployed to the
/// deterministic addresses `LibProdDeployV4` pins, a real vault+receipt
/// beacon-proxy pair, a real corporate-actions facet, and a real authoriser
/// clone — so the orchestrator's hardcoded vault-version guard
/// (`onlyExpectedVaultLogic`) reads the genuine production beacons and passes
/// (both at `initialize` and on every mint/burn). Every mint/burn then
/// exercises the real mint/redeem/receipt/rebase machinery end-to-end.
abstract contract OrchestratorIntegrationTest is Test {
    address internal constant ADMIN = address(uint160(uint256(keccak256("ADMIN"))));
    address internal constant OWNER = address(uint160(uint256(keccak256("OWNER"))));
    address internal constant MM = address(uint160(uint256(keccak256("MM"))));

    /// Beacon owner for the OARV beacon set — the address the beacon-set
    /// deployer hands ownership to at construction. Needed to upgrade the
    /// vault beacon out from under the guard (the guard-halt workflow).
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
        // at the deterministic Zoltu addresses the guard reads. MUST precede
        // the orchestrator proxy: `initialize` runs the vault-logic guard.
        LibTestDeploy.deployOffchainAssetReceiptVaultBeaconSet(vm);

        // Real corporate-actions facet at the deterministic address the
        // vault's fallback delegatecalls into.
        address facet = LibRainDeploy.deployZoltu(type(StoxCorporateActionsFacet).creationCode);
        require(facet == LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_1, "facet address mismatch");

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
        // transfers are unrestricted (the certification-lapse workflow warps
        // past this expiry).
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
                            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1
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

    /// Build the recipient's mint authorisation for an EOA recipient: sign
    /// the orchestrator's EIP-712 digest with `pk`.
    function _signedMintAuth(address token, address to, uint256 amount, bytes32 nonce, uint256 pk)
        internal
        view
        returns (MintAuthV1 memory)
    {
        Digest digest = orchestrator.mintAuthDigest(token, to, amount, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, Digest.unwrap(digest));
        return MintAuthV1({nonce: nonce, signature: abi.encodePacked(r, s, v)});
    }

    /// Build a callback-style mint authorisation: the empty signature routes
    /// verification to the recipient's `IMintRecipient.authorizeMint`.
    function _callbackMintAuth(bytes32 nonce) internal pure returns (MintAuthV1 memory) {
        return MintAuthV1({nonce: nonce, signature: ""});
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
}
