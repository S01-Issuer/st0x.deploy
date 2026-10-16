// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants, UnsupportedChainForGovernanceTimelock} from "../../../src/lib/LibTimelockInvariants.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";

contract StoxWrappedTokenVaultBeaconTest is Test {
    function deployBeacon() internal returns (address) {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
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
        assertEq(Ownable(beacon).owner(), LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
    }

    /// The owner follows the chain: the same creation code constructs a
    /// beacon owned by each chain's own governance timelock, so the Zoltu
    /// address is identical everywhere while the owner is not.
    function testBeaconOwnerIsTheActiveChainTimelock() external {
        vm.chainId(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        address beacon = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeacon).creationCode);

        assertEq(beacon, LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE, "same Zoltu address");
        assertEq(Ownable(beacon).owner(), LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ETHEREUM);
    }

    /// A chain with no pinned governance timelock cannot construct the
    /// beacon: it refuses rather than defaulting to an EOA or to another
    /// chain's timelock.
    function testBeaconRefusesAChainWithoutATimelockPin() external {
        vm.chainId(123456);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForGovernanceTimelock.selector, 123456));
        new StoxWrappedTokenVaultBeacon();
    }

    /// BEACON_INITIAL_OWNER — the owner the DEPLOYED 0.1.1 / 0.1.30
    /// artifacts bake in — is the same across V1 and V4.
    function testBeaconInitialOwnerConsistentAcrossVersions() external pure {
        assertEq(LibProdDeployV1.BEACON_INITIAL_OWNER, LibProdDeployV4.BEACON_INITIAL_OWNER);
    }

    /// Owner can upgrade implementation.
    function testUpgradeToByOwner() external {
        address beacon = deployBeacon();
        StoxWrappedTokenVault newImpl = new StoxWrappedTokenVault();
        vm.prank(LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
        UpgradeableBeacon(beacon).upgradeTo(address(newImpl));
        assertEq(UpgradeableBeacon(beacon).implementation(), address(newImpl));
    }

    /// Non-owner cannot upgrade implementation.
    function testUpgradeToByNonOwnerReverts(address nonOwner) external {
        vm.assume(nonOwner != LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
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
        vm.prank(LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
        Ownable(beacon).transferOwnership(newOwner);
        assertEq(Ownable(beacon).owner(), newOwner);
    }

    /// Non-owner cannot transfer ownership.
    function testTransferOwnershipByNonOwnerReverts(address nonOwner, address newOwner) external {
        vm.assume(nonOwner != LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
        address beacon = deployBeacon();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        Ownable(beacon).transferOwnership(newOwner);
    }

    /// renounceOwnership permanently disables upgrades.
    function testRenounceOwnershipDisablesUpgrades() external {
        address beacon = deployBeacon();
        vm.prank(LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
        Ownable(beacon).renounceOwnership();
        assertEq(Ownable(beacon).owner(), address(0));

        StoxWrappedTokenVault newImpl = new StoxWrappedTokenVault();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        UpgradeableBeacon(beacon).upgradeTo(address(newImpl));
    }
}
