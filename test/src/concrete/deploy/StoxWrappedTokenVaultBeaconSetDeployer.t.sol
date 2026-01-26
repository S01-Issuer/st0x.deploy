// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {
    StoxWrappedTokenVaultBeaconSetDeployer,
    StoxWrappedTokenVaultBeaconSetDeployerConfig,
    ZeroVaultImplementation,
    ZeroBeaconOwner,
    StoxWrappedTokenVault,
    UpgradeableBeacon
} from "src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {LibProdDeploy} from "src/lib/LibProdDeploy.sol";

contract StoxWrappedTokenVaultBeaconSetDeployerTest is Test {
    function testZeroVaultImplementationRevertConstruction(StoxWrappedTokenVaultBeaconSetDeployerConfig memory config)
        external
    {
        config.initialStoxWrappedTokenVaultImplementation = address(0);
        vm.assume(config.initialOwner != address(0));
        vm.expectRevert(ZeroVaultImplementation.selector);
        new StoxWrappedTokenVaultBeaconSetDeployer(config);
    }

    function testZeroInitialOwnerRevertConstruction(StoxWrappedTokenVaultBeaconSetDeployerConfig memory config)
        external
    {
        config.initialOwner = address(0);
        vm.assume(config.initialStoxWrappedTokenVaultImplementation != address(0));
        vm.expectRevert(ZeroBeaconOwner.selector);
        new StoxWrappedTokenVaultBeaconSetDeployer(config);
    }

    function testSuccessfulConstruction(StoxWrappedTokenVaultBeaconSetDeployerConfig memory config) external {
        vm.assume(config.initialOwner != address(0));
        config.initialStoxWrappedTokenVaultImplementation = address(new StoxWrappedTokenVault());
        StoxWrappedTokenVaultBeaconSetDeployer deployer = new StoxWrappedTokenVaultBeaconSetDeployer(config);
        assertTrue(address(deployer.I_STOX_WRAPPED_TOKEN_VAULT_BEACON()) != address(0));
        assertEq(
            address(deployer.I_STOX_WRAPPED_TOKEN_VAULT_BEACON()).codehash,
            LibProdDeploy.PROD_UPGRADEABLE_BEACON_BASE_CODEHASH_V1
        );
        assertEq(
            UpgradeableBeacon(address(deployer.I_STOX_WRAPPED_TOKEN_VAULT_BEACON())).implementation(),
            config.initialStoxWrappedTokenVaultImplementation
        );
        assertEq(UpgradeableBeacon(address(deployer.I_STOX_WRAPPED_TOKEN_VAULT_BEACON())).owner(), config.initialOwner);
    }
}
