// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IMigrationRegistryV3} from "rain-deploy-0.1.21/src/interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.21/src/lib/LibMigrationRegistryDeploy.sol";
import {
    RUNTIME_CODE as MIGRATION_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.21/src/generated/candidate/MigrationRegistry.sol";
import {LibRainDeploy} from "rain-deploy-0.1.21/src/lib/LibRainDeploy.sol";

import {
    BeaconOwnerNotBound,
    BeaconOwnerNotTimelock,
    deployBeaconsDeclaration
} from "../../script/20261022-deploy-beacons.s.sol";
import {bindBeaconOwnerDeclaration} from "../../script/20261022-bind-beacon-owner.s.sol";
import {StoxWrappedTokenVault} from "../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfigFork} from "../../src/lib/LibStoxConfigFork.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {DeployBeaconsHarness} from "./DeployBeaconsHarness.sol";

contract DeployBeaconsTest is Test {
    DeployBeaconsHarness internal script;

    function setUp() external {
        vm.chainId(8453);
        script = new DeployBeaconsHarness();
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, MIGRATION_REGISTRY_RUNTIME_CODE);
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        LibStoxConfigFork.bindBeaconOwner(vm, LibTimelockInvariants.timelockForChainId(block.chainid));
    }

    function markBound() internal {
        vm.mockCall(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            abi.encodeCall(
                IMigrationRegistryV3.appliedV3,
                (
                    LibSafeInvariants.safeForChainId(block.chainid),
                    LibStoxMigrations.NAMESPACE,
                    bindBeaconOwnerDeclaration().id
                )
            ),
            abi.encode(block.timestamp)
        );
    }

    function testDeclarationIsOntoTheBind() external pure {
        assertEq(deployBeaconsDeclaration().prerequisites[0].migration, bindBeaconOwnerDeclaration().id);
        assertEq(deployBeaconsDeclaration().namespace, LibStoxMigrations.NAMESPACE);
    }

    function testStepRefusesAnUnboundChain() external {
        vm.expectRevert(abi.encodeWithSelector(BeaconOwnerNotBound.selector, "base"));
        script.callBoundZoltuDeployStep("base", address(this), type(StoxWrappedTokenVaultBeacon).creationCode);
    }

    function testStepDeploysOnABoundChain() external {
        markBound();
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
