// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibProdDeployV2} from "../../../../src/lib/LibProdDeployV2.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";

/// @title StoxProdV2Test
/// @notice Fork tests verifying all V2 Zoltu deployments exist on all
/// supported networks with expected codehashes. These tests will fail until
/// V2 is deployed on-chain.
contract StoxProdV2Test is Test {
    function _checkAllV2OnChain() internal view {
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
    }

    /// All V2 contracts MUST be deployed on Arbitrum.
    function testProdDeployArbitrumV2() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        _checkAllV2OnChain();
    }

    /// All V2 contracts MUST be deployed on Base.
    function testProdDeployBaseV2() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        _checkAllV2OnChain();
    }

    /// All V2 contracts MUST be deployed on Base Sepolia.
    function testProdDeployBaseSepoliaV2() external {
        vm.createSelectFork(LibRainDeploy.BASE_SEPOLIA);
        _checkAllV2OnChain();
    }

    /// All V2 contracts MUST be deployed on Flare.
    function testProdDeployFlareV2() external {
        vm.createSelectFork(LibRainDeploy.FLARE);
        _checkAllV2OnChain();
    }

    /// All V2 contracts MUST be deployed on Polygon.
    function testProdDeployPolygonV2() external {
        vm.createSelectFork(LibRainDeploy.POLYGON);
        _checkAllV2OnChain();
    }
}
