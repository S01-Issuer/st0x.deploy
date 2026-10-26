// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";
import {IConfigRegistryV3} from "rain-deploy-0.1.22/src/interface/IConfigRegistryV3.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibStoxConfigFork} from "../../../src/lib/LibStoxConfigFork.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";

contract StoxWrappedTokenVaultBeaconTest is Test {
    address internal constant OWNER = LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK;

    function deployBeacon() internal returns (address) {
        LibStoxConfigFork.bindBeaconOwner(vm, OWNER);
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        return LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeacon).creationCode);
    }

    /// Beacon deploys via Zoltu with correct implementation and owner.
    function testBeaconConstructsWithExpectedConstants() external {
        address beacon = deployBeacon();

        assertEq(beacon, LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE);
        assertEq(
            StoxWrappedTokenVaultBeacon(beacon).implementation(), LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_CANDIDATE
        );
        assertEq(Ownable(beacon).owner(), OWNER);
    }

    /// The owner is the bound beacon owner, and the Zoltu address does not
    /// depend on it.
    function testFuzzBeaconOwnerFollowsBinding(address owner) external {
        vm.assume(owner != address(0));
        LibStoxConfigFork.bindBeaconOwner(vm, owner);
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        address beacon = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeacon).creationCode);
        assertEq(beacon, LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE);
        assertEq(Ownable(beacon).owner(), owner);
    }

    /// An unbound owner refuses construction.
    function testBeaconOwnerUnboundReverts() external {
        LibStoxConfigFork.etchConfigRegistry(vm);
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV3.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.BEACON_OWNER_NAME
            )
        );
        new StoxWrappedTokenVaultBeacon();
    }

    /// BEACON_INITIAL_OWNER is the same across V1 and V4.
    function testBeaconInitialOwnerConsistentAcrossVersions() external pure {
        assertEq(LibProdDeployV1.BEACON_INITIAL_OWNER, LibProdDeployV4.BEACON_INITIAL_OWNER);
    }

    /// Owner can upgrade implementation.
    function testUpgradeToByOwner() external {
        address beacon = deployBeacon();
        StoxWrappedTokenVault newImpl = new StoxWrappedTokenVault();
        vm.prank(OWNER);
        UpgradeableBeacon(beacon).upgradeTo(address(newImpl));
        assertEq(UpgradeableBeacon(beacon).implementation(), address(newImpl));
    }

    /// Non-owner cannot upgrade implementation.
    function testUpgradeToByNonOwnerReverts(address nonOwner) external {
        vm.assume(nonOwner != OWNER);
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
        vm.prank(OWNER);
        Ownable(beacon).transferOwnership(newOwner);
        assertEq(Ownable(beacon).owner(), newOwner);
    }

    /// Non-owner cannot transfer ownership.
    function testTransferOwnershipByNonOwnerReverts(address nonOwner, address newOwner) external {
        vm.assume(nonOwner != OWNER);
        address beacon = deployBeacon();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        Ownable(beacon).transferOwnership(newOwner);
    }

    /// renounceOwnership permanently disables upgrades.
    function testRenounceOwnershipDisablesUpgrades() external {
        address beacon = deployBeacon();
        vm.prank(OWNER);
        Ownable(beacon).renounceOwnership();
        assertEq(Ownable(beacon).owner(), address(0));

        StoxWrappedTokenVault newImpl = new StoxWrappedTokenVault();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        UpgradeableBeacon(beacon).upgradeTo(address(newImpl));
    }
}
