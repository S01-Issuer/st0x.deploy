// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {StoxUnifiedDeployer} from "../../../../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {LibProdDeploy} from "../../../../src/lib/LibProdDeploy.sol";
import {LibTestProd} from "../../../lib/LibTestProd.sol";

contract StoxProdBaseTest is Test {
    function _checkAllContracts() internal view {
        assertTrue(
            LibProdDeploy.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER.code.length > 0,
            "OffchainAssetReceiptVaultBeaconSetDeployer not deployed"
        );
        assertEq(
            LibProdDeploy.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER.codehash,
            LibProdDeploy.PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1
        );

        assertTrue(
            LibProdDeploy.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER.code.length > 0,
            "StoxWrappedTokenVaultBeaconSetDeployer not deployed"
        );
        assertEq(
            LibProdDeploy.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER.codehash,
            LibProdDeploy.PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1
        );

        assertTrue(
            LibProdDeploy.STOX_WRAPPED_TOKEN_VAULT.code.length > 0,
            "StoxWrappedTokenVault not deployed"
        );
        assertEq(
            LibProdDeploy.STOX_WRAPPED_TOKEN_VAULT.codehash,
            LibProdDeploy.PROD_STOX_WRAPPED_TOKEN_VAULT_BASE_CODEHASH_V1
        );

        assertTrue(
            LibProdDeploy.STOX_UNIFIED_DEPLOYER.code.length > 0,
            "StoxUnifiedDeployer not deployed"
        );
        assertEq(
            LibProdDeploy.STOX_UNIFIED_DEPLOYER.codehash,
            LibProdDeploy.PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1
        );
    }

    /// Fresh-compiled StoxUnifiedDeployer must match the stored codehash.
    function testProdStoxUnifiedDeployerFreshCodehash() external {
        StoxUnifiedDeployer fresh = new StoxUnifiedDeployer();
        assertEq(address(fresh).codehash, LibProdDeploy.PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1);
    }

    /// All contracts MUST be deployed on Base.
    function testProdDeployBase() external {
        LibTestProd.createSelectForkBase(vm);
        _checkAllContracts();
    }
}
