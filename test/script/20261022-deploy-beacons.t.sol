// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IConfigRegistryV3} from "rain-deploy-0.1.22/src/interface/IConfigRegistryV3.sol";
import {LibRainDeploy} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";

import {BeaconOwnerNotTimelock} from "../../script/20261022-deploy-beacons.s.sol";
import {StoxWrappedTokenVault} from "../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxConfigFork} from "../../src/lib/LibStoxConfigFork.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {DeployBeaconsHarness} from "./DeployBeaconsHarness.sol";

contract DeployBeaconsTest is Test {
    DeployBeaconsHarness internal script;

    function setUp() external {
        vm.chainId(8453);
        script = new DeployBeaconsHarness();
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        LibStoxConfigFork.etchConfigRegistry(vm);
    }

    function testStepRefusesAnUnboundChain() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV3.NameNotRegistered.selector, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_OWNER
            )
        );
        script.callBoundZoltuDeployStep("base", address(this), type(StoxWrappedTokenVaultBeacon).creationCode);
    }

    function testStepDeploysOnABoundChain() external {
        LibStoxConfigFork.bindBeaconOwner(vm, LibTimelockInvariants.timelockForChainId(block.chainid));
        address beacon =
            script.callBoundZoltuDeployStep("base", address(this), type(StoxWrappedTokenVaultBeacon).creationCode);
        assertEq(beacon, LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE);
        assertEq(Ownable(beacon).owner(), LibTimelockInvariants.timelockForChainId(block.chainid));
        script.callAssertTimelockOwned(beacon);
    }

    function testFuzzAssertTimelockOwnedRefusesAnotherOwner(address owner) external {
        vm.assume(owner != LibTimelockInvariants.timelockForChainId(block.chainid) && owner != address(0));
        LibStoxConfigFork.bindBeaconOwner(vm, owner);
        address beacon = address(new StoxWrappedTokenVaultBeacon());
        vm.expectRevert(abi.encodeWithSelector(BeaconOwnerNotTimelock.selector, beacon, owner));
        script.callAssertTimelockOwned(beacon);
    }
}
