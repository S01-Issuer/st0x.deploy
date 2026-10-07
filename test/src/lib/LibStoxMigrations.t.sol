// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "rain-deploy-0.1.15/src/lib/LibRainDeploy.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.15/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.15/src/lib/LibMigrationRegistryDeploy.sol";

import {LibOrchestratorInvariants} from "../../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations, NoGovernanceTimelockMigrationOnChain} from "../../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibStoxMigrationsHarness} from "./LibStoxMigrationsHarness.sol";

/// @title LibStoxMigrationsTest
/// @notice The migration ids name their scripts, and the pinned execution
/// moment of the governance-timelock migration is the chain's own record of
/// it: the block's timestamp, in the block that holds the orchestrator
/// beacon's ownership transfer from the Safe to the timelock.
contract LibStoxMigrationsTest is Test {
    /// @notice The st0x.deploy records live at this registry instance. A
    /// rain-deploy bump that moves it strands every record already written,
    /// so it must fail here, with a reason, before it reaches the role
    /// invariants.
    function testRegistryInstancePinned() external pure {
        assertEq(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            0xc89F95eC7e626CFBef37a1F502A69BaF2022F8A8,
            "st0x.deploy migration records live at this registry instance; moving it strands them"
        );
        assertEq(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
            0x7a67fcb1f620333d4214ee9a6674bcd505c72aad173a6e8579b8c1371db45684,
            "st0x.deploy migration records live at this registry instance; moving it strands them"
        );
    }

    function testNamespace() external pure {
        assertEq(LibStoxMigrations.NAMESPACE, keccak256("st0x.deploy"));
    }

    function testIdsNameTheirScripts() external pure {
        assertEq(
            LibStoxMigrations.GOVERNANCE_TIMELOCK, keccak256("script/20260729-migrate-governance-to-timelock.s.sol")
        );
        assertEq(
            LibStoxMigrations.ORCHESTRATOR_EMERGENCY, keccak256("script/20261006-grant-orchestrator-emergency.s.sol")
        );
        assertEq(
            LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
            keccak256("script/20261006-orchestrator-admin-to-timelock.s.sol")
        );
    }

    function testIdsDistinct() external pure {
        assertTrue(LibStoxMigrations.GOVERNANCE_TIMELOCK != LibStoxMigrations.ORCHESTRATOR_EMERGENCY);
        assertTrue(LibStoxMigrations.ORCHESTRATOR_EMERGENCY != LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        assertTrue(LibStoxMigrations.GOVERNANCE_TIMELOCK != LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
    }

    function testUnknownChainReverts() external {
        LibStoxMigrationsHarness ext = new LibStoxMigrationsHarness();
        vm.expectRevert(abi.encodeWithSelector(NoGovernanceTimelockMigrationOnChain.selector, uint256(42161)));
        ext.governanceTimelockExecution(42161);
    }

    function assertExecution(string memory network) internal {
        vm.createSelectFork(network);
        LibMigrationRegistry.checkCodeHash();
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        (uint256 appliedAt, uint256 blockNumber) = LibStoxMigrations.governanceTimelockExecution(block.chainid);

        bytes32[] memory topics = new bytes32[](3);
        topics[0] = keccak256("OwnershipTransferred(address,address)");
        topics[1] = bytes32(uint256(uint160(safe)));
        topics[2] = bytes32(uint256(uint160(timelock)));
        Vm.EthGetLogs[] memory logs =
            vm.eth_getLogs(blockNumber, blockNumber, LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON, topics);
        assertEq(logs.length, 1, string.concat(network, ": ownership transfers in the pinned block"));

        // A fork at the pinned block reads its header; no state at that
        // block is touched, so no archive node is needed.
        vm.createSelectFork(network, blockNumber);
        assertEq(block.timestamp, appliedAt, string.concat(network, ": timestamp"));
    }

    function testGovernanceTimelockExecutionBase() external {
        assertExecution(LibRainDeploy.BASE);
    }

    function testGovernanceTimelockExecutionEthereum() external {
        assertExecution(LibStoxDeployNetworks.ETHEREUM);
    }

    function testGovernanceTimelockExecutionHyperEvm() external {
        assertExecution(LibStoxDeployNetworks.HYPEREVM);
    }

    function testGovernanceTimelockExecutionRobinhood() external {
        assertExecution(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testGovernanceTimelockExecutionBsc() external {
        assertExecution(LibStoxDeployNetworks.BSC);
    }
}
