// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {
    IOffchainAssetReceiptVaultBeaconSetDeployerV2
} from "rain-vats-0.1.6/src/interface/IOffchainAssetReceiptVaultBeaconSetDeployerV2.sol";

/// @title StoxProdV4Test
/// @notice Fork test verifying every V4 Zoltu deployment exists on-chain at its
/// pinned address with the expected runtime codehash.
///
/// The two production networks carry different sets:
/// - Base carries the full accumulated set — the audited 0.1.1 contracts plus
///   the later orchestrator and rebuilds that the rolling `candidate` snapshot
///   tracks — deployed incrementally over those releases.
/// - Ethereum mainnet carries only the audited 0.1.1 production set, shipped by
///   `script/DeployProdV4_0_1_1.sol` from the stored 0.1.1 creation code. The
///   orchestrator and the later rebuilds are Base-only.
///
/// The codehash pins are the same literals `LibProdDeployV4Test` checks against
/// the generated pointer files and against a fresh Zoltu redeploy. This test
/// closes the loop by asserting the *live on-chain* code at each deterministic
/// address matches those pins, proving the production deploy landed the audited
/// bytecode at the address the source expects.
///
/// `STOX_PROD_AUTHORISER_V4_CLONE` (hydrated from the 2026-07 broadcast) is
/// not checked here; `LibProdDeployV4Test.testAuthoriserV4ClonePin` asserts
/// the literal + codehash derivation, and `StoxProdV4PostSwap.t.sol` checks
/// the live on-chain clone.
contract StoxProdV4Test is Test {
    /// Asserts the audited 0.1.1 production set is present at its pinned
    /// addresses with the pinned codehashes; that the wrapped-token-vault beacon
    /// points at the 0.1.1 vault implementation; and that the
    /// offchain-asset-receipt-vault beacon-set deployer's two beacons point at
    /// the 0.1.1 receipt and receipt vault implementations. This is the exact
    /// set shipped to Ethereum mainnet, and a subset of Base.
    ///
    /// Deliberately says nothing about beacon OWNERSHIP: that is live
    /// operational state, and it only matters for the beacons production
    /// tokens actually run on — asserted per chain via
    /// `LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe` in the network
    /// tests. On Base the 0.1.1-address beacons checked here are an unadopted
    /// deploy artifact whose owner is irrelevant; on Ethereum they ARE the
    /// in-use beacons and the per-chain assert covers them.
    function checkProd_0_1_1OnChain() internal view {
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
        // implementation — constructor wiring of the deploy artifact.
        assertEq(
            IBeacon(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1).implementation(),
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1,
            "V4 beacon implementation mismatch"
        );

        // The offchain-asset-receipt-vault beacon-set deployer creates two
        // beacons in its constructor: the receipt beacon points at the 0.1.1
        // receipt implementation and the offchain-asset-receipt-vault beacon
        // points at the 0.1.1 receipt vault implementation.
        IOffchainAssetReceiptVaultBeaconSetDeployerV2 oarvDeployer = IOffchainAssetReceiptVaultBeaconSetDeployerV2(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1
        );

        IBeacon receiptBeacon = oarvDeployer.iReceiptBeacon();
        assertEq(
            receiptBeacon.implementation(),
            LibProdDeployV4.STOX_RECEIPT_0_1_1,
            "V4 OARV receipt beacon implementation mismatch"
        );

        IBeacon vaultBeacon = oarvDeployer.iOffchainAssetReceiptVaultBeacon();
        assertEq(
            vaultBeacon.implementation(),
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1,
            "V4 OARV vault beacon implementation mismatch"
        );
    }

    /// The Base fork verifies only the frozen audited 0.1.1 set — that is what
    /// the in-use Base production beacons (the V1-generation addresses) actually
    /// adopt on-chain. The rolling `candidate` snapshot regenerates from source
    /// and is NEVER a deploy target, so its addresses are not checked on any fork;
    /// `testCandidateSelfConsistent` verifies candidate == current source locally
    /// instead. The in-use beacons MUST be owned by Base's token-owner Safe.
    function testProdDeployBaseV4() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        checkProd_0_1_1OnChain();
        LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe(block.chainid);
    }

    /// Only the audited 0.1.1 production set is shipped to Ethereum mainnet (the
    /// orchestrator and candidate rebuilds are Base-only), so the Ethereum fork is
    /// checked against the 0.1.1 set alone. On Ethereum the 0.1.1 beacons ARE
    /// the in-use production beacons, and the beacon-ownership migration
    /// (`20260716-migrate-beacon-owners-ethereum`) has transferred them to
    /// Ethereum's token-owner Safe — asserted via the per-chain in-use pin.
    function testProdDeployEthereumV4() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        checkProd_0_1_1OnChain();
        LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe(block.chainid);
    }

    /// Only the audited 0.1.1 production set ships to HyperEVM (the RAI-1511
    /// bootstrap), mirroring Ethereum. Loudly PENDING until the shared rainix
    /// test workflow carries a HyperEVM RPC secret; once forkable, RED until
    /// the 0.1.1 suites land (the impl-deploy forcing function), then until
    /// the beacon-owner migration hands the in-use beacons to the HyperEVM
    /// Safe — then green, catching drift thereafter.
    function testProdDeployHyperEvmV4() external {
        if (bytes(vm.envOr("HYPEREVM_RPC_URL", string(""))).length == 0) {
            emit log("PENDING: HYPEREVM_RPC_URL not available in this environment (RAI-1511)");
            return;
        }
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        checkProd_0_1_1OnChain();
        LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe(block.chainid);
    }
}
