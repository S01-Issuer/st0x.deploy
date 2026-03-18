// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer,
    ZeroVaultAsset
} from "../../../../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {StoxWrappedTokenVault} from "../../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {MockERC20} from "../../../concrete/MockERC20.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";
import {LibProdDeployV2} from "../../../../src/lib/LibProdDeployV2.sol";

contract StoxWrappedTokenVaultBeaconSetDeployerTest is Test {
    /// newStoxWrappedTokenVault reverts with ZeroVaultAsset when asset is
    /// address(0).
    function testNewVaultZeroAsset() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        vm.expectRevert(abi.encodeWithSelector(ZeroVaultAsset.selector));
        StoxWrappedTokenVaultBeaconSetDeployer(LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER)
            .newStoxWrappedTokenVault(address(0));
    }

    /// newStoxWrappedTokenVault succeeds with valid asset.
    function testNewVaultSuccess() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));
        assertTrue(address(vault) != address(0));
        assertEq(vault.asset(), address(asset));
    }
}
