// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibMigrationInvariant} from "../../../../src/lib/LibMigrationInvariant.sol";
import {FLEET_UPGRADE_DEADLINE} from "../../../lib/LibTestProd.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibRainDeploy} from "rain-deploy-0.1.11/src/lib/LibRainDeploy.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {
    IOffchainAssetReceiptVaultBeaconSetDeployerV2
} from "rain-vats-0.2.1/src/interface/IOffchainAssetReceiptVaultBeaconSetDeployerV2.sol";

/// @title StoxProdV4Test
/// @notice Fork test verifying the audited 0.1.1 production set exists
/// on-chain at its pinned address with the pinned runtime code on every
/// production chain. The codehash pins are the same literals
/// `LibProdDeployV4Test` checks against the generated pointer files.
///
/// `STOX_PROD_AUTHORISER_V4_CLONE` is not checked here;
/// `LibProdDeployV4Test.testAuthoriserV4ClonePin` asserts the literal +
/// codehash derivation, and `StoxProdV4PostSwap.t.sol` checks the live
/// on-chain clone.
contract StoxProdV4Test is Test {
    /// Asserts the audited 0.1.1 production set is present at its pinned
    /// addresses with the pinned codehashes and runtime code; that the
    /// wrapped-token-vault beacon points at the 0.1.1 vault implementation;
    /// and that the offchain-asset-receipt-vault beacon-set deployer's two
    /// beacons point at the expected receipt and receipt vault
    /// implementations. Beacon ownership is asserted per chain via
    /// `LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe`.
    /// @param oarvBeaconsAreInUse Whether the OARV deployer's two beacons are
    /// the chain's in-use production beacons. False on Base, where production
    /// runs on the V1-address beacons.
    function checkProd_0_1_1OnChain(bool oarvBeaconsAreInUse) internal view {
        assertTrue(LibProdDeployV4.STOX_RECEIPT_0_1_1.code.length > 0, "V4 StoxReceipt not deployed");
        assertEq(LibProdDeployV4.STOX_RECEIPT_0_1_1.codehash, LibProdDeployV4.STOX_RECEIPT_CODEHASH_0_1_1);
        assertEq(LibProdDeployV4.STOX_RECEIPT_0_1_1.code, LibProdDeployV4.STOX_RECEIPT_RUNTIME_CODE_0_1_1);

        assertTrue(LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1.code.length > 0, "V4 StoxReceiptVault not deployed");
        assertEq(LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1.codehash, LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_1);
        assertEq(LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1.code, LibProdDeployV4.STOX_RECEIPT_VAULT_RUNTIME_CODE_0_1_1);

        assertTrue(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1.code.length > 0, "V4 StoxWrappedTokenVault not deployed"
        );
        assertEq(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1.codehash,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_CODEHASH_0_1_1
        );
        assertEq(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1.code,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_RUNTIME_CODE_0_1_1
        );

        assertTrue(LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1.code.length > 0, "V4 StoxUnifiedDeployer not deployed");
        assertEq(
            LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1.codehash, LibProdDeployV4.STOX_UNIFIED_DEPLOYER_CODEHASH_0_1_1
        );
        assertEq(
            LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1.code, LibProdDeployV4.STOX_UNIFIED_DEPLOYER_RUNTIME_CODE_0_1_1
        );

        assertTrue(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1.code.length > 0,
            "V4 StoxWrappedTokenVaultBeacon not deployed"
        );
        assertEq(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1.codehash,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH_0_1_1
        );
        assertEq(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1.code,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_RUNTIME_CODE_0_1_1
        );

        assertTrue(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1.code.length > 0,
            "V4 StoxWrappedTokenVaultBeaconSetDeployer not deployed"
        );
        assertEq(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1.codehash,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_1
        );
        assertEq(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1.code,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_1
        );

        assertTrue(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1.code.length > 0,
            "V4 StoxOffchainAssetReceiptVaultBeaconSetDeployer not deployed"
        );
        assertEq(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1.codehash,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_1
        );
        assertEq(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1.code,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_1
        );

        assertTrue(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1.code.length > 0,
            "V4 StoxOffchainAssetReceiptVaultAuthorizerV1 not deployed"
        );
        assertEq(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1.codehash,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_0_1_1
        );
        assertEq(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1.code,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RUNTIME_CODE_0_1_1
        );

        assertTrue(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_0_1_1.code.length > 0,
            "V4 StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 not deployed"
        );
        assertEq(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_0_1_1.codehash,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH_0_1_1
        );
        assertEq(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_0_1_1.code,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_RUNTIME_CODE_0_1_1
        );

        assertTrue(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_1.code.length > 0,
            "V4 StoxCorporateActionsFacet not deployed"
        );
        assertEq(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_1.codehash,
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_0_1_1
        );
        assertEq(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_1.code,
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_RUNTIME_CODE_0_1_1
        );

        // The wrapped-token-vault beacon points at the 0.1.1 vault
        // implementation.
        assertEq(
            IBeacon(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1).implementation(),
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1,
            "V4 beacon implementation mismatch"
        );

        // The offchain-asset-receipt-vault beacon-set deployer's two beacons.
        IOffchainAssetReceiptVaultBeaconSetDeployerV2 oarvDeployer = IOffchainAssetReceiptVaultBeaconSetDeployerV2(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1
        );

        IBeacon receiptBeacon = oarvDeployer.iReceiptBeacon();
        IBeacon vaultBeacon = oarvDeployer.iOffchainAssetReceiptVaultBeacon();
        if (oarvBeaconsAreInUse) {
            // In-use production beacons ride the fleet-upgrade migration
            // window: 0.1.1 or 0.1.30 until `FLEET_UPGRADE_DEADLINE`, 0.1.30
            // only after.
            LibMigrationInvariant.assertMigration(
                "OARV receipt beacon implementation()",
                receiptBeacon.implementation(),
                LibProdDeployV4.STOX_RECEIPT_0_1_1,
                LibProdDeployV4.STOX_RECEIPT_0_1_30,
                FLEET_UPGRADE_DEADLINE
            );
            LibMigrationInvariant.assertMigration(
                "OARV vault beacon implementation()",
                vaultBeacon.implementation(),
                LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1,
                LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30,
                FLEET_UPGRADE_DEADLINE
            );
        } else {
            // Not in use: still at the 0.1.1 impls their constructor baked.
            assertEq(
                receiptBeacon.implementation(),
                LibProdDeployV4.STOX_RECEIPT_0_1_1,
                "V4 OARV receipt beacon implementation mismatch"
            );
            assertEq(
                vaultBeacon.implementation(),
                LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1,
                "V4 OARV vault beacon implementation mismatch"
            );
        }
    }

    /// The 0.1.1 set on Base. The in-use beacons (the V1-generation
    /// addresses) are owned by Base's token-owner Safe. The rolling
    /// `candidate` snapshot is not a deploy target and is not checked on any
    /// fork.
    function testProdDeployBaseV4() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        checkProd_0_1_1OnChain(false);
        LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe(block.chainid);
    }

    /// The 0.1.1 set on Ethereum. The 0.1.1 beacons are the in-use
    /// production beacons, owned by Ethereum's token-owner Safe.
    function testProdDeployEthereumV4() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        checkProd_0_1_1OnChain(true);
        LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe(block.chainid);
    }

    /// The 0.1.1 set on HyperEVM, with its in-use beacons owned by the
    /// HyperEVM token-owner Safe. Forks unconditionally; needs
    /// `HYPEREVM_RPC_URL`.
    function testProdDeployHyperEvmV4() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        checkProd_0_1_1OnChain(true);
        LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe(block.chainid);
    }

    /// The 0.1.1 set on Robinhood Chain, with its in-use beacons owned by
    /// the Robinhood Chain token-owner Safe. Forks unconditionally; needs
    /// `ROBINHOOD_RPC_URL`.
    function testProdDeployRobinhoodV4() external {
        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        checkProd_0_1_1OnChain(true);
        LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe(block.chainid);
    }

    /// The 0.1.1 set on BNB Smart Chain, with its in-use beacons owned by
    /// the BNB Smart Chain token-owner Safe.
    function testProdDeployBscV4() external {
        vm.createSelectFork(LibStoxDeployNetworks.BSC);
        checkProd_0_1_1OnChain(true);
        LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe(block.chainid);
    }
}
