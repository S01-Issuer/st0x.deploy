// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants, UnsupportedChainForTokenOwnerSafe} from "../../../src/lib/LibSafeInvariants.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";

contract StoxWrappedTokenVaultBeaconTest is Test {
    /// The beacon owner is the active chain's token-owner Safe, so the
    /// local chain is pinned to Base before construction.
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
        assertEq(Ownable(beacon).owner(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
    }

    /// The owner follows the chain: the same creation code constructs a
    /// beacon owned by each chain's own token-owner Safe, so the Zoltu
    /// address is identical everywhere while the owner is not.
    function testBeaconOwnerIsTheActiveChainSafe() external {
        vm.chainId(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        address beacon = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeacon).creationCode);

        assertEq(beacon, LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE, "same Zoltu address");
        assertEq(Ownable(beacon).owner(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM);
    }

    /// A chain with no pinned token-owner Safe cannot construct the beacon:
    /// there is no owner to hand upgrade authority to, so the deploy refuses
    /// rather than defaulting to an EOA or to another chain's Safe.
    function testBeaconRefusesAChainWithoutASafePin() external {
        vm.chainId(123456);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForTokenOwnerSafe.selector, 123456));
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
        vm.prank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        UpgradeableBeacon(beacon).upgradeTo(address(newImpl));
        assertEq(UpgradeableBeacon(beacon).implementation(), address(newImpl));
    }

    /// Non-owner cannot upgrade implementation.
    function testUpgradeToByNonOwnerReverts(address nonOwner) external {
        vm.assume(nonOwner != LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
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
        vm.prank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        Ownable(beacon).transferOwnership(newOwner);
        assertEq(Ownable(beacon).owner(), newOwner);
    }

    /// Non-owner cannot transfer ownership.
    function testTransferOwnershipByNonOwnerReverts(address nonOwner, address newOwner) external {
        vm.assume(nonOwner != LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        address beacon = deployBeacon();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        Ownable(beacon).transferOwnership(newOwner);
    }

    /// renounceOwnership permanently disables upgrades.
    function testRenounceOwnershipDisablesUpgrades() external {
        address beacon = deployBeacon();
        vm.prank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        Ownable(beacon).renounceOwnership();
        assertEq(Ownable(beacon).owner(), address(0));

        StoxWrappedTokenVault newImpl = new StoxWrappedTokenVault();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        UpgradeableBeacon(beacon).upgradeTo(address(newImpl));
    }
}
