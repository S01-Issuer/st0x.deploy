// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std/Test.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibTestProd} from "../../lib/LibTestProd.sol";
import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {ICLONEABLE_V2_SUCCESS} from "rain.factory/interface/ICloneableV2.sol";

/// @title StoxWrappedTokenVaultV1ProdBaseTest
/// @notice Fork tests demonstrating V1 on-chain behaviour that differs from
/// V2. Each test documents a specific behavioural change.
contract StoxWrappedTokenVaultV1ProdBaseTest is Test {
    function _v1Beacon() internal returns (address) {
        LibTestProd.createSelectForkBase(vm);
        (bool ok, bytes memory data) = LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            .staticcall(abi.encodeWithSignature("I_STOX_WRAPPED_TOKEN_VAULT_BEACON()"));
        assertTrue(ok, "V1 beacon call failed");
        return abi.decode(data, (address));
    }

    /// V1 StoxWrappedTokenVault allows initializing with address(0) as the
    /// asset without reverting. V2 reverts with ZeroAsset.
    function testProdV1ZeroAssetDoesNotRevert() external {
        address beacon = _v1Beacon();
        BeaconProxy proxy = new BeaconProxy(beacon, "");

        (bool initOk, bytes memory initData) =
            address(proxy).call(abi.encodeWithSignature("initialize(bytes)", abi.encode(address(0))));
        assertTrue(initOk, "V1 initialize with zero address should not revert");
        assertEq(abi.decode(initData, (bytes32)), ICLONEABLE_V2_SUCCESS);
    }

    /// V1 BeaconSetDeployer exposes the beacon via the old
    /// I_STOX_WRAPPED_TOKEN_VAULT_BEACON() selector. V2 renames to
    /// iStoxWrappedTokenVaultBeacon().
    function testProdV1OldBeaconSelectorWorks() external {
        LibTestProd.createSelectForkBase(vm);

        // V1 selector works.
        (bool oldOk,) = LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            .staticcall(abi.encodeWithSignature("I_STOX_WRAPPED_TOKEN_VAULT_BEACON()"));
        assertTrue(oldOk, "V1 old selector should work");

        // V2 selector does NOT work on V1 deployment.
        (bool newOk,) = LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            .staticcall(abi.encodeWithSignature("iStoxWrappedTokenVaultBeacon()"));
        assertFalse(newOk, "V2 selector should not work on V1 deployment");
    }

    /// V1 BeaconSetDeployer emits Deployment event AFTER the initialize call.
    /// V2 emits it BEFORE (checks-effects-interactions).
    function testProdV1DeploymentEventAfterInitialize() external {
        address beacon = _v1Beacon();
        address asset = IBeacon(beacon).implementation();

        vm.recordLogs();
        (bool ok,) = LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            .call(abi.encodeWithSignature("newStoxWrappedTokenVault(address)", asset));
        assertTrue(ok, "V1 newStoxWrappedTokenVault should succeed");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(logs.length > 0, "should have logs");

        bytes32 deploymentTopic = keccak256("Deployment(address,address)");
        bytes32 initTopic = keccak256("StoxWrappedTokenVaultInitialized(address,address)");

        // In V1, Deployment is the LAST event (emitted after initialize).
        assertEq(logs[logs.length - 1].topics[0], deploymentTopic, "V1 Deployment should be last event");

        // Init event comes before Deployment.
        bool foundInitBeforeDeployment = false;
        for (uint256 i = 0; i < logs.length - 1; i++) {
            if (logs[i].topics[0] == initTopic) {
                foundInitBeforeDeployment = true;
                break;
            }
        }
        assertTrue(foundInitBeforeDeployment, "V1 init event should come before Deployment event");
    }
}
