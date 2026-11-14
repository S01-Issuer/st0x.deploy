// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibST0xOrchestratorProxy} from "../../../src/generated/LibST0xOrchestratorProxy.sol";
import {LibOrchestratorInvariants} from "../../../src/lib/LibOrchestratorInvariants.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LibTestOrchestratorDeploy} from "../../lib/LibTestOrchestratorDeploy.sol";

contract LibST0xOrchestratorProxyTest is Test {
    function testRuntimeCodeIsTheDeployedInstances() external {
        address timelock = makeAddr("timelock");
        LibTestDeploy.bindBeaconInitialOwner(vm, timelock);
        LibTestDeploy.bindOrchestratorInitialAdmin(vm, timelock);
        address instance = LibTestOrchestratorDeploy.deployAll(vm, makeAddr("deployer"));
        assertEq(instance, LibOrchestratorInvariants.mintCapsInstance(), "instance");
        assertEq(instance.code, LibST0xOrchestratorProxy.RUNTIME_CODE, "runtime code");
        assertEq(instance.codehash, keccak256(LibST0xOrchestratorProxy.RUNTIME_CODE), "codehash");
    }
}
