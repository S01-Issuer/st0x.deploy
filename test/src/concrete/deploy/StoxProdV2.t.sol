// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibProdDeployV2} from "../../../../src/lib/LibProdDeployV2.sol";
import {LibProdDeployV2BaseOverrides} from "../../../../src/lib/LibProdDeployV2BaseOverrides.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {
    OffchainAssetReceiptVaultBeaconSetDeployer
} from "ethgild/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";

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

        // OARV deployer: verify internal beacon implementations and owners.
        OffchainAssetReceiptVaultBeaconSetDeployer oarvDeployer = OffchainAssetReceiptVaultBeaconSetDeployer(
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

    /// All V2 contracts MUST be deployed on Arbitrum.
    function testProdDeployArbitrumV2() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        checkAllV2OnChain();
    }

    /// All V2 contracts MUST be deployed on Base.
    /// OARV deployer beacons on Base were corrupted post-deployment — see
    /// LibProdDeployV2BaseOverrides for details.
    function testProdDeployBaseV2() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        checkAllV2OnChain(
            LibProdDeployV2BaseOverrides.RECEIPT_BEACON_IMPLEMENTATION,
            LibProdDeployV2BaseOverrides.RECEIPT_BEACON_OWNER,
            LibProdDeployV2BaseOverrides.VAULT_BEACON_IMPLEMENTATION,
            LibProdDeployV2BaseOverrides.VAULT_BEACON_OWNER
        );
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
