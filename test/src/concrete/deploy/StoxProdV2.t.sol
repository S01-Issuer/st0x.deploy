// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibProdDeployV2} from "../../../../src/lib/LibProdDeployV2.sol";
import {LibProdDeployV2BaseOverrides} from "../../../../src/lib/LibProdDeployV2BaseOverrides.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibInvariants} from "../../../../src/lib/LibInvariants.sol";
import {IGnosisSafe} from "../../../../src/interface/IGnosisSafe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {
    IOffchainAssetReceiptVaultBeaconSetDeployerV1
} from "rain-vats-0.1.7/src/interface/IOffchainAssetReceiptVaultBeaconSetDeployerV1.sol";

/// @title StoxProdV2Test
/// @notice Fork tests verifying all V2 Zoltu deployments exist on all
/// supported networks with expected codehashes. These tests will fail until
/// V2 is deployed on-chain.
contract StoxProdV2Test is Test {
    function checkAllV2OnChain(
        address expectedReceiptBeaconImpl,
        address expectedReceiptBeaconOwner,
        address expectedVaultBeaconImpl,
        address expectedVaultBeaconOwner
    ) internal view {
        assertTrue(LibProdDeployV2.STOX_RECEIPT.code.length > 0, "V2 StoxReceipt not deployed");
        assertEq(LibProdDeployV2.STOX_RECEIPT.codehash, LibProdDeployV2.STOX_RECEIPT_CODEHASH);

        assertTrue(LibProdDeployV2.STOX_RECEIPT_VAULT.code.length > 0, "V2 StoxReceiptVault not deployed");
        assertEq(LibProdDeployV2.STOX_RECEIPT_VAULT.codehash, LibProdDeployV2.STOX_RECEIPT_VAULT_CODEHASH);

        assertTrue(LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT.code.length > 0, "V2 StoxWrappedTokenVault not deployed");
        assertEq(LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT.codehash, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_CODEHASH);

        assertTrue(
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON.code.length > 0,
            "V2 StoxWrappedTokenVaultBeacon not deployed"
        );
        assertEq(
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON.codehash,
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH
        );

        assertTrue(
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER.code.length > 0,
            "V2 StoxWrappedTokenVaultBeaconSetDeployer not deployed"
        );
        assertEq(
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER.codehash,
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH
        );

        assertTrue(
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER.code.length > 0,
            "V2 StoxOffchainAssetReceiptVaultBeaconSetDeployer not deployed"
        );
        assertEq(
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER.codehash,
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH
        );

        assertTrue(LibProdDeployV2.STOX_UNIFIED_DEPLOYER.code.length > 0, "V2 StoxUnifiedDeployer not deployed");
        assertEq(LibProdDeployV2.STOX_UNIFIED_DEPLOYER.codehash, LibProdDeployV2.STOX_UNIFIED_DEPLOYER_CODEHASH);

        assertTrue(
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1.code.length > 0,
            "V2 StoxOffchainAssetReceiptVaultAuthorizerV1 not deployed"
        );
        assertEq(
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1.codehash,
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH
        );

        assertTrue(
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1.code.length > 0,
            "V2 StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 not deployed"
        );
        assertEq(
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1.codehash,
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH
        );

        // Wrapped token vault beacon: verify implementation and owner.
        assertEq(
            IBeacon(LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON).implementation(),
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT,
            "V2 beacon implementation mismatch"
        );
        assertEq(
            Ownable(LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON).owner(),
            LibProdDeployV2.BEACON_INITIAL_OWNER,
            "V2 beacon owner mismatch"
        );

        // OARV deployer: on-chain V2 has V1 ABI (I_RECEIPT_BEACON selectors).
        IOffchainAssetReceiptVaultBeaconSetDeployerV1 oarvDeployer = IOffchainAssetReceiptVaultBeaconSetDeployerV1(
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
        );

        IBeacon receiptBeacon = oarvDeployer.I_RECEIPT_BEACON();
        assertEq(receiptBeacon.implementation(), expectedReceiptBeaconImpl, "V2 receipt beacon implementation mismatch");
        assertEq(
            Ownable(address(receiptBeacon)).owner(), expectedReceiptBeaconOwner, "V2 receipt beacon owner mismatch"
        );

        IBeacon vaultBeacon = oarvDeployer.I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON();
        assertEq(vaultBeacon.implementation(), expectedVaultBeaconImpl, "V2 vault beacon implementation mismatch");
        assertEq(Ownable(address(vaultBeacon)).owner(), expectedVaultBeaconOwner, "V2 vault beacon owner mismatch");
    }

    /// Default check for networks where beacons are in the expected state.
    function checkAllV2OnChain() internal view {
        checkAllV2OnChain(
            LibProdDeployV2.STOX_RECEIPT,
            LibProdDeployV2.BEACON_INITIAL_OWNER,
            LibProdDeployV2.STOX_RECEIPT_VAULT,
            LibProdDeployV2.BEACON_INITIAL_OWNER
        );
    }

    /// Per-Safe invariant bundle for the ST0x token-owner Safe on Base.
    /// Calls `LibInvariants.assertAll` against the production Safe
    /// address pinned in `LibSafeInvariants` — composes the Safe-side and
    /// token-side invariants in one call. The Safe is Base-only (no Safe
    /// on Arbitrum / Base Sepolia / Flare / Polygon for ST0x ops), so
    /// this helper is only invoked from `testProdDeployBaseV2`.
    function checkAllSafeBase() internal view {
        LibInvariants.assertAll(IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE));
    }

    /// All V2 contracts MUST be deployed on Arbitrum.
    function testProdDeployArbitrumV2() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        checkAllV2OnChain();
    }

    /// All V2 contracts MUST be deployed on Base.
    /// OARV deployer beacons on Base were corrupted post-deployment — see
    /// LibProdDeployV2BaseOverrides for details.
    /// Also pins the ST0x token-owner Safe's invariants against the live
    /// Base head fork via `checkAllSafeBase` — Base is the only network
    /// where the Safe is deployed, so this is the unique site where the
    /// Safe-state pins are exercised against on-chain reality.
    function testProdDeployBaseV2() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        checkAllV2OnChain(
            LibProdDeployV2BaseOverrides.RECEIPT_BEACON_IMPLEMENTATION,
            LibProdDeployV2BaseOverrides.RECEIPT_BEACON_OWNER,
            LibProdDeployV2BaseOverrides.VAULT_BEACON_IMPLEMENTATION,
            LibProdDeployV2BaseOverrides.VAULT_BEACON_OWNER
        );
        checkAllSafeBase();
    }

    /// All V2 contracts MUST be deployed on Base Sepolia.
    function testProdDeployBaseSepoliaV2() external {
        vm.createSelectFork(LibRainDeploy.BASE_SEPOLIA);
        checkAllV2OnChain();
    }

    /// All V2 contracts MUST be deployed on Flare.
    function testProdDeployFlareV2() external {
        vm.createSelectFork(LibRainDeploy.FLARE);
        checkAllV2OnChain();
    }

    /// All V2 contracts MUST be deployed on Polygon.
    function testProdDeployPolygonV2() external {
        vm.createSelectFork(LibRainDeploy.POLYGON);
        checkAllV2OnChain();
    }
}
