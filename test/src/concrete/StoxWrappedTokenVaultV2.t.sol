// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std/Test.sol";
import {StoxWrappedTokenVault, ZeroAsset} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer,
    ZeroVaultAsset
} from "../../../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {LibProdDeployV3} from "../../../src/lib/LibProdDeployV3.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {MockERC20} from "../../concrete/MockERC20.sol";

/// @title StoxWrappedTokenVaultV2Test
/// @notice Tests V2-specific behaviour changes that differ from V1.
contract StoxWrappedTokenVaultV2Test is Test {
    /// V2 StoxWrappedTokenVault reverts with ZeroAsset when initialized with
    /// address(0). This is the fix for the V1 vulnerability.
    function testV2ZeroAssetReverts() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        vm.expectRevert(abi.encodeWithSelector(ZeroVaultAsset.selector));
        StoxWrappedTokenVaultBeaconSetDeployer(LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER)
            .newStoxWrappedTokenVault(address(0));
    }

    /// V2 StoxWrappedTokenVaultBeaconSetDeployer emits Deployment event
    /// BEFORE the initialize call (checks-effects-interactions).
    function testV2DeploymentEventBeforeInitialize() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();

        vm.recordLogs();
        StoxWrappedTokenVaultBeaconSetDeployer(LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER)
            .newStoxWrappedTokenVault(address(asset));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(logs.length > 0, "should have logs");

        bytes32 deploymentTopic = keccak256("Deployment(address,address)");
        bytes32 initTopic = keccak256("StoxWrappedTokenVaultInitialized(address,address)");

        // Find positions of both events.
        uint256 deploymentIndex = type(uint256).max;
        uint256 initIndex = type(uint256).max;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == deploymentTopic && deploymentIndex == type(uint256).max) {
                deploymentIndex = i;
            }
            if (logs[i].topics[0] == initTopic && initIndex == type(uint256).max) {
                initIndex = i;
            }
        }

        assertTrue(deploymentIndex != type(uint256).max, "Deployment event not found");
        assertTrue(initIndex != type(uint256).max, "Init event not found");
        // V2: Deployment emits BEFORE init (opposite of V1).
        assertTrue(deploymentIndex < initIndex, "V2 Deployment should come before init event");
    }

    /// V2 StoxWrappedTokenVaultBeaconSetDeployer successfully creates a vault
    /// with the correct asset.
    function testV2NewVaultSuccess() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));

        assertEq(vault.asset(), address(asset));
        assertEq(vault.name(), "Wrapped Test Token");
        assertEq(vault.symbol(), "wTT");
    }
}
