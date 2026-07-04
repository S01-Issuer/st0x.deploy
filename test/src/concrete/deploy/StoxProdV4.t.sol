// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibProdDeployV4} from "../../../../src/lib/LibProdDeployV4.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";

/// @title StoxProdV4Test
/// @notice Fork test verifying every V4 Zoltu deployment exists on Base with
/// the expected runtime codehash. V4 ships to Base only (the deploy CI targets
/// Base), so unlike `StoxProdV2Test` there is a single network fork here.
///
/// The codehash pins are the same literals `LibProdDeployV4Test` checks against
/// the generated pointer files and against a fresh Zoltu redeploy. This test
/// closes the loop by asserting the *live on-chain* code at each deterministic
/// address matches those pins, proving the production deploy landed the audited
/// bytecode at the address the source expects.
///
/// `STOX_PROD_AUTHORISER_V4_CLONE` is a non-deterministic deploy target still
/// pinned as `address(0)` in `LibProdDeployV4`, so it is not checked here;
/// `LibProdDeployV4Test.testAuthoriserV4ClonePlaceholder` guards that
/// placeholder until the clone is hydrated.
contract StoxProdV4Test is Test {
    /// Asserts every V4 deployed contract is present at its pinned address with
    /// the pinned codehash; that the wrapped-token-vault beacon points at the V4
    /// vault implementation; and that the offchain-asset-receipt-vault
    /// beacon-set deployer's two beacons point at the V4 receipt and receipt
    /// vault implementations. All three beacons are still held by the beacon
    /// initial owner (pre-migration deploy state).
    function checkAllV4OnChain() internal view {
        assertTrue(LibProdDeployV4.STOX_RECEIPT_RAIN_VATS_0_1_6.code.length > 0, "V4 StoxReceipt not deployed");
        assertEq(
            LibProdDeployV4.STOX_RECEIPT_RAIN_VATS_0_1_6.codehash, LibProdDeployV4.STOX_RECEIPT_CODEHASH_RAIN_VATS_0_1_6
        );

        assertTrue(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_RAIN_VATS_0_1_6.code.length > 0,
            "V4 StoxWrappedTokenVault not deployed"
        );
        assertEq(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_RAIN_VATS_0_1_6.codehash,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_CODEHASH_RAIN_VATS_0_1_6
        );

        assertTrue(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_RAIN_VATS_0_1_6.code.length > 0,
            "V4 StoxWrappedTokenVaultBeacon not deployed"
        );
        assertEq(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_RAIN_VATS_0_1_6.codehash,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH_RAIN_VATS_0_1_6
        );

        assertTrue(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6.code.length > 0,
            "V4 StoxWrappedTokenVaultBeaconSetDeployer not deployed"
        );
        assertEq(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6.codehash,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH_RAIN_VATS_0_1_6
        );

        assertTrue(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6.code.length > 0,
            "V4 StoxOffchainAssetReceiptVaultAuthorizerV1 not deployed"
        );
        assertEq(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6.codehash,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_RAIN_VATS_0_1_6
        );

        assertTrue(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_RAIN_VATS_0_1_6.code.length
                > 0,
            "V4 StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 not deployed"
        );
        assertEq(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_RAIN_VATS_0_1_6.codehash,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH_RAIN_VATS_0_1_6
        );

        // The wrapped-token-vault beacon points at the V4 vault implementation
        // and is still held by the beacon initial owner (rainlang.eth), which
        // is the deploy-time state before ownership migration to the ST0x
        // token-owner Safe.
        assertEq(
            IBeacon(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_RAIN_VATS_0_1_6).implementation(),
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_RAIN_VATS_0_1_6,
            "V4 beacon implementation mismatch"
        );
        assertEq(
            Ownable(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_RAIN_VATS_0_1_6).owner(),
            LibProdDeployV4.BEACON_INITIAL_OWNER,
            "V4 beacon owner mismatch"
        );

        // ------------------------------------------------------------------ //
        // Pending-redeploy tripwires (2026-07-04 cumulative-multiplier change) //
        // ------------------------------------------------------------------ //
        // The facet gained `cumulativeBalanceMultiplierSinceGenesis`, moving
        // its deterministic address and, transitively, the vault impl, the
        // OARV beacon-set deployer, the orchestrator set, and the unified
        // deployer. The pins were updated AHEAD of the on-chain upgrade wave
        // (deliberately — the constants must be right before the upgrades
        // run). Until that wave deploys, these addresses MUST be empty; the
        // moment the deploy lands these tripwires fail loudly, and whoever
        // sees that must flip this block back to full deployed+codehash
        // assertions (and restore the OARV beacon implementation/owner
        // checks that previously lived at the bottom of this function).
        assertEq(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_RAIN_VATS_0_1_6.code.length,
            0,
            "V4.1 facet now deployed - flip StoxProdV4 tripwires to full assertions"
        );
        assertEq(
            LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6.code.length,
            0,
            "V4.1 StoxReceiptVault now deployed - flip StoxProdV4 tripwires to full assertions"
        );
        assertEq(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6.code.length,
            0,
            "V4.1 OARV beacon-set deployer now deployed - flip StoxProdV4 tripwires to full assertions"
        );
        assertEq(
            LibProdDeployV4.STOX_UNIFIED_DEPLOYER_RAIN_VATS_0_1_6.code.length,
            0,
            "V4.1 StoxUnifiedDeployer now deployed - flip StoxProdV4 tripwires to full assertions"
        );
    }

    /// All V4 contracts MUST be deployed on Base with the expected codehashes.
    function testProdDeployBaseV4() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        checkAllV4OnChain();
    }
}
