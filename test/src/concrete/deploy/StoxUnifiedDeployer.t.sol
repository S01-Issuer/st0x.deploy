// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultConfigV2,
    OffchainAssetReceiptVault
} from "ethgild/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {StoxUnifiedDeployer} from "../../../../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {StoxWrappedTokenVault} from "../../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeaconSetDeployer} from "../../../../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";

contract StoxUnifiedDeployerTest is Test {
    function testStoxUnifiedDeployer(address asset, address vault, OffchainAssetReceiptVaultConfigV2 memory config)
        external
    {
        vm.assume(asset.code.length == 0);
        vm.assume(vault.code.length == 0);
        StoxUnifiedDeployer unifiedDeployer = new StoxUnifiedDeployer();

        vm.etch(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
            vm.getCode("OffchainAssetReceiptVaultBeaconSetDeployer")
        );
        vm.mockCall(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
            abi.encodeWithSelector(
                OffchainAssetReceiptVaultBeaconSetDeployer.newOffchainAssetReceiptVault.selector, config
            ),
            abi.encode(asset)
        );

        vm.etch(
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER,
            vm.getCode("StoxWrappedTokenVaultBeaconSetDeployer.sol:StoxWrappedTokenVaultBeaconSetDeployer")
        );
        vm.mockCall(
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER,
            abi.encodeWithSelector(StoxWrappedTokenVaultBeaconSetDeployer.newStoxWrappedTokenVault.selector, asset),
            abi.encode(address(vault))
        );

        vm.expectEmit();
        emit StoxUnifiedDeployer.Deployment(address(this), asset, vault);
        unifiedDeployer.newTokenAndWrapperVault(config);
    }

    /// Reverts from the first deployer propagate through.
    function testStoxUnifiedDeployerRevertsFirstDeployer(OffchainAssetReceiptVaultConfigV2 memory config) external {
        StoxUnifiedDeployer unifiedDeployer = new StoxUnifiedDeployer();

        vm.etch(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
            vm.getCode("OffchainAssetReceiptVaultBeaconSetDeployer")
        );
        vm.mockCallRevert(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
            abi.encodeWithSelector(
                OffchainAssetReceiptVaultBeaconSetDeployer.newOffchainAssetReceiptVault.selector, config
            ),
            abi.encodeWithSignature("ZeroInitialAdmin()")
        );

        vm.expectRevert(abi.encodeWithSignature("ZeroInitialAdmin()"));
        unifiedDeployer.newTokenAndWrapperVault(config);
    }

    /// Reverts from the second deployer propagate through.
    function testStoxUnifiedDeployerRevertsSecondDeployer(
        address asset,
        OffchainAssetReceiptVaultConfigV2 memory config
    ) external {
        vm.assume(asset.code.length == 0);
        StoxUnifiedDeployer unifiedDeployer = new StoxUnifiedDeployer();

        vm.etch(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
            vm.getCode("OffchainAssetReceiptVaultBeaconSetDeployer")
        );
        vm.mockCall(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
            abi.encodeWithSelector(
                OffchainAssetReceiptVaultBeaconSetDeployer.newOffchainAssetReceiptVault.selector, config
            ),
            abi.encode(asset)
        );

        vm.etch(
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER,
            vm.getCode("StoxWrappedTokenVaultBeaconSetDeployer.sol:StoxWrappedTokenVaultBeaconSetDeployer")
        );
        vm.mockCallRevert(
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER,
            abi.encodeWithSelector(StoxWrappedTokenVaultBeaconSetDeployer.newStoxWrappedTokenVault.selector, asset),
            abi.encodeWithSignature("ZeroVaultAsset()")
        );

        vm.expectRevert(abi.encodeWithSignature("ZeroVaultAsset()"));
        unifiedDeployer.newTokenAndWrapperVault(config);
    }
}
