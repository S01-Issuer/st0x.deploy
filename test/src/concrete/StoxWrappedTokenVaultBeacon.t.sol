// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV2} from "../../../src/lib/LibProdDeployV2.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract StoxWrappedTokenVaultBeaconTest is Test {
    function deployBeacon() internal returns (address) {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        return LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeacon).creationCode);
    }

    /// Beacon deploys via Zoltu with correct implementation and owner.
    function testBeaconConstructsWithExpectedConstants() external {
        address beacon = deployBeacon();

        assertEq(beacon, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON);
        assertEq(StoxWrappedTokenVaultBeacon(beacon).implementation(), LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT);
        assertEq(Ownable(beacon).owner(), LibProdDeployV2.BEACON_INITIAL_OWNER);
    }

    /// BEACON_INITIAL_OWNER is the same across V1 and V2.
    function testBeaconInitialOwnerConsistentAcrossVersions() external pure {
        assertEq(LibProdDeployV1.BEACON_INITIAL_OWNER, LibProdDeployV2.BEACON_INITIAL_OWNER);
    }

    /// Owner can upgrade implementation.
    function testUpgradeToByOwner() external {
        address beacon = deployBeacon();
        StoxWrappedTokenVault newImpl = new StoxWrappedTokenVault();
        vm.prank(LibProdDeployV2.BEACON_INITIAL_OWNER);
        UpgradeableBeacon(beacon).upgradeTo(address(newImpl));
        assertEq(UpgradeableBeacon(beacon).implementation(), address(newImpl));
    }

    /// Non-owner cannot upgrade implementation.
    function testUpgradeToByNonOwnerReverts(address nonOwner) external {
        vm.assume(nonOwner != LibProdDeployV2.BEACON_INITIAL_OWNER);
        address beacon = deployBeacon();
        StoxWrappedTokenVault newImpl = new StoxWrappedTokenVault();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        UpgradeableBeacon(beacon).upgradeTo(address(newImpl));
    }

    /// Owner can transfer ownership.
    function testTransferOwnership(address newOwner) external {
        vm.assume(newOwner != address(0));
        address beacon = deployBeacon();
        vm.prank(LibProdDeployV2.BEACON_INITIAL_OWNER);
        Ownable(beacon).transferOwnership(newOwner);
        assertEq(Ownable(beacon).owner(), newOwner);
    }

    /// Non-owner cannot transfer ownership.
    function testTransferOwnershipByNonOwnerReverts(address nonOwner, address newOwner) external {
        vm.assume(nonOwner != LibProdDeployV2.BEACON_INITIAL_OWNER);
        address beacon = deployBeacon();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        Ownable(beacon).transferOwnership(newOwner);
    }

    /// renounceOwnership permanently disables upgrades.
    function testRenounceOwnershipDisablesUpgrades() external {
        address beacon = deployBeacon();
        vm.prank(LibProdDeployV2.BEACON_INITIAL_OWNER);
        Ownable(beacon).renounceOwnership();
        assertEq(Ownable(beacon).owner(), address(0));

        StoxWrappedTokenVault newImpl = new StoxWrappedTokenVault();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        UpgradeableBeacon(beacon).upgradeTo(address(newImpl));
    }
}
