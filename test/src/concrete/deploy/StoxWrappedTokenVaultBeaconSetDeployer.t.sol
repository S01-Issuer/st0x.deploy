// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer,
    StoxWrappedTokenVaultBeaconSetDeployerConfig,
    ZeroVaultImplementation,
    ZeroBeaconOwner,
    ZeroVaultAsset
} from "../../../../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {StoxWrappedTokenVault, ZeroAsset} from "../../../../src/concrete/StoxWrappedTokenVault.sol";

contract StoxWrappedTokenVaultBeaconSetDeployerTest is Test {
    /// Constructor reverts with ZeroVaultImplementation when implementation is
    /// address(0).
    function testConstructZeroVaultImplementation(address initialOwner) external {
        vm.assume(initialOwner != address(0));
        vm.expectRevert(abi.encodeWithSelector(ZeroVaultImplementation.selector));
        new StoxWrappedTokenVaultBeaconSetDeployer(
            StoxWrappedTokenVaultBeaconSetDeployerConfig({
                initialOwner: initialOwner,
                initialStoxWrappedTokenVaultImplementation: address(0)
            })
        );
    }

    /// Constructor reverts with ZeroBeaconOwner when owner is address(0).
    function testConstructZeroBeaconOwner() external {
        StoxWrappedTokenVault implementation = new StoxWrappedTokenVault();
        vm.expectRevert(abi.encodeWithSelector(ZeroBeaconOwner.selector));
        new StoxWrappedTokenVaultBeaconSetDeployer(
            StoxWrappedTokenVaultBeaconSetDeployerConfig({
                initialOwner: address(0),
                initialStoxWrappedTokenVaultImplementation: address(implementation)
            })
        );
    }

    /// Constructor succeeds and sets beacon implementation correctly.
    function testConstructSuccess(address initialOwner) external {
        vm.assume(initialOwner != address(0));
        StoxWrappedTokenVault implementation = new StoxWrappedTokenVault();
        StoxWrappedTokenVaultBeaconSetDeployer deployer = new StoxWrappedTokenVaultBeaconSetDeployer(
            StoxWrappedTokenVaultBeaconSetDeployerConfig({
                initialOwner: initialOwner,
                initialStoxWrappedTokenVaultImplementation: address(implementation)
            })
        );
        assertEq(deployer.I_STOX_WRAPPED_TOKEN_VAULT_BEACON().implementation(), address(implementation));
    }

    /// newStoxWrappedTokenVault reverts with ZeroVaultAsset when asset is
    /// address(0).
    function testNewVaultZeroAsset(address initialOwner) external {
        vm.assume(initialOwner != address(0));
        StoxWrappedTokenVault implementation = new StoxWrappedTokenVault();
        StoxWrappedTokenVaultBeaconSetDeployer deployer = new StoxWrappedTokenVaultBeaconSetDeployer(
            StoxWrappedTokenVaultBeaconSetDeployerConfig({
                initialOwner: initialOwner,
                initialStoxWrappedTokenVaultImplementation: address(implementation)
            })
        );
        vm.expectRevert(abi.encodeWithSelector(ZeroVaultAsset.selector));
        deployer.newStoxWrappedTokenVault(address(0));
    }

    /// newStoxWrappedTokenVault succeeds, emits Deployment, returns valid
    /// vault with correct asset.
    function testNewVaultSuccess(address initialOwner) external {
        vm.assume(initialOwner != address(0));
        StoxWrappedTokenVault implementation = new StoxWrappedTokenVault();
        StoxWrappedTokenVaultBeaconSetDeployer deployer = new StoxWrappedTokenVaultBeaconSetDeployer(
            StoxWrappedTokenVaultBeaconSetDeployerConfig({
                initialOwner: initialOwner,
                initialStoxWrappedTokenVaultImplementation: address(implementation)
            })
        );
        // Use the implementation address as a non-zero asset stand-in.
        address asset = address(implementation);
        StoxWrappedTokenVault vault = deployer.newStoxWrappedTokenVault(asset);
        assertTrue(address(vault) != address(0));
        assertEq(vault.asset(), asset);
    }
}
