// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";

import {StoxGovernanceTimelock} from "../../../src/concrete/StoxGovernanceTimelock.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

contract StoxGovernanceTimelockTest is Test {
    function deployTimelock(address safe) internal returns (TimelockController) {
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bind(
            vm, LibRegistryAuthority.ROOT_AUTHORITY, LibStoxConfig.GOVERNANCE_SAFE_NAME, "address", abi.encode(safe)
        );
        LibRainDeploy.etchZoltuFactory(vm);
        return TimelockController(payable(LibRainDeploy.deployZoltu(type(StoxGovernanceTimelock).creationCode)));
    }

    function testProposerAndCancellerAreTheBoundGovernanceSafe(address safe) external {
        TimelockController timelock = deployTimelock(safe);
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), safe), "proposer");
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), safe), "canceller");
    }

    function testConstructorGrantsOnlySafeProposalOpenExecutionAndSelfAdministration(address safe) external {
        vm.recordLogs();
        TimelockController timelock = deployTimelock(safe);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32[4] memory roles = [
            timelock.DEFAULT_ADMIN_ROLE(), timelock.PROPOSER_ROLE(), timelock.CANCELLER_ROLE(), timelock.EXECUTOR_ROLE()
        ];
        address[4] memory accounts = [address(timelock), safe, safe, address(0)];
        uint256 granted = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(timelock) || logs[i].topics[0] != IAccessControl.RoleGranted.selector) {
                continue;
            }
            assertLt(granted, roles.length, "unexpected grant");
            assertEq(logs[i].topics[1], roles[granted], "role");
            assertEq(logs[i].topics[2], bytes32(uint256(uint160(accounts[granted]))), "account");
            granted++;
        }
        assertEq(granted, roles.length, "grant count");
    }

    function testNoAccountButTheTimelockAdministersIt(address safe) external {
        vm.assume(safe != LibProdDeployV4.STOX_GOVERNANCE_TIMELOCK_CANDIDATE);
        TimelockController timelock = deployTimelock(safe);
        bytes32 admin = timelock.DEFAULT_ADMIN_ROLE();
        assertTrue(timelock.hasRole(admin, address(timelock)), "self");
        assertFalse(timelock.hasRole(admin, safe), "safe");
        assertFalse(timelock.hasRole(admin, LibRainDeploy.ZOLTU_FACTORY), "deployer");
        assertFalse(timelock.hasRole(admin, address(this)), "sender");
        assertFalse(timelock.hasRole(admin, address(0)), "zero");
    }

    function testAnyCallerExecutesAMaturedOperation(address safe, address caller) external {
        TimelockController timelock = deployTimelock(safe);
        address target = address(0xC0FFEE);
        bytes32 salt = keccak256("open-execution");

        vm.prank(safe);
        timelock.schedule(target, 0, "", bytes32(0), salt, LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.prank(caller);
        timelock.execute(target, 0, "", bytes32(0), salt);

        assertTrue(timelock.isOperationDone(timelock.hashOperation(target, 0, "", bytes32(0), salt)), "done");
    }

    function testMinDelayIsTheTimelockInvariantsMinDelay(address safe) external {
        assertEq(deployTimelock(safe).getMinDelay(), LibTimelockInvariants.TIMELOCK_MIN_DELAY);
    }

    function testDeployRevertsWhileTheRootAuthorityHasNotBoundTheGovernanceSafe() external {
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bind(
            vm, address(0xA11CE), LibStoxConfig.GOVERNANCE_SAFE_NAME, "address", abi.encode(address(0x5AFE))
        );
        // Plain CREATE: the Zoltu factory drops the constructor's revert data.
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxConfig.GOVERNANCE_SAFE_NAME
            )
        );
        new StoxGovernanceTimelock();
    }

    function testAddressAndCodehashAreTheSameOnEveryChain(uint64 chainId, address safe) external {
        vm.chainId(chainId);
        TimelockController timelock = deployTimelock(safe);
        assertEq(address(timelock), LibProdDeployV4.STOX_GOVERNANCE_TIMELOCK_CANDIDATE, "address");
        assertEq(address(timelock).codehash, LibProdDeployV4.STOX_GOVERNANCE_TIMELOCK_CODEHASH_CANDIDATE, "codehash");
    }
}
