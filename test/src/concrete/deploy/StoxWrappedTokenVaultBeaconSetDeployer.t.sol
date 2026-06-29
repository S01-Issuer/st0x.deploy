// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.1/src/Test.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer,
    ZeroVaultAsset,
    InitializeVaultFailed
} from "../../../../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {StoxWrappedTokenVault} from "../../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {MockERC20} from "../../../concrete/MockERC20.sol";
import {BadInitializeVault} from "../../../concrete/BadInitializeVault.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";
import {LibProdDeployV4} from "../../../../src/lib/LibProdDeployV4.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";

contract StoxWrappedTokenVaultBeaconSetDeployerTest is Test {
    /// newStoxWrappedTokenVault reverts with ZeroVaultAsset when asset is
    /// address(0).
    function testNewVaultZeroAsset() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        vm.expectRevert(abi.encodeWithSelector(ZeroVaultAsset.selector));
        StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6
            ).newStoxWrappedTokenVault(address(0));
    }

    /// newStoxWrappedTokenVault succeeds with valid asset and emits
    /// Deployment with correct sender and vault address.
    function testNewVaultSuccess() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVaultBeaconSetDeployer deployer = StoxWrappedTokenVaultBeaconSetDeployer(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6
        );

        vm.recordLogs();
        StoxWrappedTokenVault vault = deployer.newStoxWrappedTokenVault(address(asset));

        assertTrue(address(vault) != address(0));
        assertEq(vault.asset(), address(asset));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundDeployment = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(deployer)) {
                foundDeployment = true;
                (address sender, address vaultAddr) = abi.decode(logs[i].data, (address, address));
                assertEq(sender, address(this), "event sender should be this contract");
                assertEq(vaultAddr, address(vault), "event vault address should match returned vault");
            }
        }
        assertTrue(foundDeployment, "Deployment event should have been emitted");
    }

    /// newStoxWrappedTokenVault reverts with InitializeVaultFailed when the
    /// implementation returns a value other than ICLONEABLE_V2_SUCCESS.
    function testNewVaultInitializeVaultFailed() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        BadInitializeVault badImpl = new BadInitializeVault();
        vm.prank(LibProdDeployV4.BEACON_INITIAL_OWNER);
        UpgradeableBeacon(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_RAIN_VATS_0_1_6).upgradeTo(address(badImpl));

        vm.expectRevert(abi.encodeWithSelector(InitializeVaultFailed.selector));
        StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6
            ).newStoxWrappedTokenVault(address(1));
    }
}
