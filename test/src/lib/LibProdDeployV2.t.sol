// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";
import {LibProdDeployV2} from "../../../src/lib/LibProdDeployV2.sol";

/// @title LibProdDeployV2Test
/// @notice Validates that V2's frozen creation-bytecode constants are the
/// authentic historical code. Each test deploys the frozen `hex` literal
/// through the Zoltu factory and asserts the deterministic address and runtime
/// codehash equal the V2 pins. Crucially these deploy the frozen constants, not
/// `type(X).creationCode`, so the assertions are independent of the current
/// compiler/optimizer settings: a legacy version is a historical audit trail,
/// never a recompile target (that role belongs to the latest version's test).
/// Contracts whose constructor reads a dependency's code (the beacon, the set
/// deployers) deploy that dependency's frozen creation code first, exactly as
/// the original Zoltu deployment ordering required.
contract LibProdDeployV2Test is Test {
    function testV2CreationCodeStoxReceipt() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(LibProdDeployV2.PROD_STOX_RECEIPT_CREATION_BYTECODE_V2);
        assertEq(deployed, LibProdDeployV2.STOX_RECEIPT);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV2.STOX_RECEIPT_CODEHASH);
    }

    function testV2CreationCodeStoxReceiptVault() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(LibProdDeployV2.PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V2);
        assertEq(deployed, LibProdDeployV2.STOX_RECEIPT_VAULT);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV2.STOX_RECEIPT_VAULT_CODEHASH);
    }

    function testV2CreationCodeStoxWrappedTokenVault() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(LibProdDeployV2.PROD_STOX_WRAPPED_TOKEN_VAULT_CREATION_BYTECODE_V2);
        assertEq(deployed, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_CODEHASH);
    }

    function testV2CreationCodeStoxUnifiedDeployer() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(LibProdDeployV2.PROD_STOX_UNIFIED_DEPLOYER_CREATION_BYTECODE_V2);
        assertEq(deployed, LibProdDeployV2.STOX_UNIFIED_DEPLOYER);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV2.STOX_UNIFIED_DEPLOYER_CODEHASH);
    }

    /// The beacon constructor reverts unless the implementation it points at
    /// already has code, so deploy the V2 wrapped token vault first.
    function testV2CreationCodeStoxWrappedTokenVaultBeacon() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(LibProdDeployV2.PROD_STOX_WRAPPED_TOKEN_VAULT_CREATION_BYTECODE_V2);
        address deployed =
            LibRainDeploy.deployZoltu(LibProdDeployV2.PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_CREATION_BYTECODE_V2);
        assertEq(deployed, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH);
    }

    /// The offchain set deployer reads the receipt and receipt vault
    /// implementations in its constructor, so deploy those first.
    function testV2CreationCodeStoxOffchainAssetReceiptVaultBeaconSetDeployer() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(LibProdDeployV2.PROD_STOX_RECEIPT_CREATION_BYTECODE_V2);
        LibRainDeploy.deployZoltu(LibProdDeployV2.PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V2);
        address deployed = LibRainDeploy.deployZoltu(
            LibProdDeployV2.PROD_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V2
        );
        assertEq(deployed, LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH);
    }

    /// The wrapped token vault set deployer reads the beacon in its
    /// constructor, which in turn needs the wrapped token vault, so deploy
    /// both first in order.
    function testV2CreationCodeStoxWrappedTokenVaultBeaconSetDeployer() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(LibProdDeployV2.PROD_STOX_WRAPPED_TOKEN_VAULT_CREATION_BYTECODE_V2);
        LibRainDeploy.deployZoltu(LibProdDeployV2.PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_CREATION_BYTECODE_V2);
        address deployed = LibRainDeploy.deployZoltu(
            LibProdDeployV2.PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V2
        );
        assertEq(deployed, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH);
    }

    function testV2CreationCodeStoxOffchainAssetReceiptVaultAuthorizerV1() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(
            LibProdDeployV2.PROD_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CREATION_BYTECODE_V2
        );
        assertEq(deployed, LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH);
    }

    function testV2CreationCodeStoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(
            LibProdDeployV2.PROD_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CREATION_BYTECODE_V2
        );
        assertEq(deployed, LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1);
        assertTrue(deployed.code.length > 0);
        assertEq(
            deployed.codehash, LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH
        );
    }
}
