// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.19/src/lib/LibMigrationRegistry.sol";
import {
    IMigrationRegistryV3,
    MIGRATION_HEAD_GENESIS,
    Prerequisite
} from "rain-deploy-0.1.19/src/interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.19/src/lib/LibMigrationRegistryDeploy.sol";
import {
    RUNTIME_CODE as MIGRATION_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.19/src/generated/candidate/MigrationRegistry.sol";

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
            0x1F0e0A54489B8fE29C3aB2e3500295DC84c7D58f,
            "st0x.deploy migration records live at this registry instance; moving it strands them"
        );
        assertEq(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
            0x9c93685df075fff2be0849da0572b05ac94302d08ac9347659b08d48336ebe24,
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

    /// @notice A catalogued network ST0x does not deploy to has no moment.
    function testUndeployedCataloguedChainReverts() external {
        LibStoxMigrationsHarness ext = new LibStoxMigrationsHarness();
        vm.expectRevert(abi.encodeWithSelector(NoGovernanceTimelockMigrationOnChain.selector, uint256(42161)));
        ext.governanceTimelockExecution(42161);
    }

    /// @notice A chain id the catalogue does not name has no moment.
    function testUncataloguedChainReverts() external {
        LibStoxMigrationsHarness ext = new LibStoxMigrationsHarness();
        vm.expectRevert(abi.encodeWithSelector(NoGovernanceTimelockMigrationOnChain.selector, uint256(31337)));
        ext.governanceTimelockExecution(31337);
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

    /// @notice Every network ST0x deploys to has a pinned execution moment,
    /// and it is the chain's own record of the migration.
    function testGovernanceTimelockExecutionOnEveryDeploymentNetwork() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            assertExecution(networks[i]);
        }
    }

    /// @notice The pinned registry's own code at its address, so the call
    /// builders' code-hash check passes without a fork.
    function etchRegistry() internal {
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, MIGRATION_REGISTRY_RUNTIME_CODE);
    }

    /// @notice The registry call names the writer, binds this repo's
    /// namespace and targets the pinned registry.
    function testApplyMigrationCallBindsTheNamespace() external {
        etchRegistry();
        address writer = makeAddr("writer");
        Prerequisite[] memory prerequisites = LibStoxMigrations.onto(writer, MIGRATION_HEAD_GENESIS);

        (address to, bytes memory data) =
            LibStoxMigrations.applyMigrationCall(writer, LibStoxMigrations.ORCHESTRATOR_EMERGENCY, prerequisites);

        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(
            data,
            abi.encodeCall(
                IMigrationRegistryV3.applyMigrationV3,
                (writer, LibStoxMigrations.NAMESPACE, LibStoxMigrations.ORCHESTRATOR_EMERGENCY, prerequisites)
            )
        );
    }

    /// @notice The history call names the writer, binds this repo's
    /// namespace, carries the moment and targets the pinned registry.
    function testApplyMigrationHistoryCallBindsTheNamespace() external {
        etchRegistry();
        address writer = makeAddr("writer");
        Prerequisite[] memory prerequisites = LibStoxMigrations.onto(writer, MIGRATION_HEAD_GENESIS);

        (address to, bytes memory data) = LibStoxMigrations.applyMigrationHistoryCall(
            writer, LibStoxMigrations.GOVERNANCE_TIMELOCK, 1_791_056_759, prerequisites
        );

        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(
            data,
            abi.encodeCall(
                IMigrationRegistryV3.applyMigrationHistoryV3,
                (
                    writer,
                    LibStoxMigrations.NAMESPACE,
                    LibStoxMigrations.GOVERNANCE_TIMELOCK,
                    1_791_056_759,
                    prerequisites
                )
            )
        );
    }

    /// @notice Both calls, sent by the writer, land in the writer's line in
    /// this repo's namespace, and the reads see them there: the history
    /// record at its moment, the direct record at the block it lands in, the
    /// head at the latest.
    function testCallsSentByTheWriterLandInItsLine() external {
        etchRegistry();
        vm.warp(1_800_000_000);
        address writer = makeAddr("writer");
        assertEq(LibStoxMigrations.head(writer), MIGRATION_HEAD_GENESIS);

        (address historyTo, bytes memory historyData) = LibStoxMigrations.applyMigrationHistoryCall(
            writer,
            LibStoxMigrations.GOVERNANCE_TIMELOCK,
            1_791_056_759,
            LibStoxMigrations.onto(writer, MIGRATION_HEAD_GENESIS)
        );
        vm.prank(writer);
        (bool historyOk,) = historyTo.call(historyData);
        assertTrue(historyOk, "history record");

        (address recordTo, bytes memory recordData) = LibStoxMigrations.applyMigrationCall(
            writer,
            LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
            LibStoxMigrations.onto(writer, LibStoxMigrations.GOVERNANCE_TIMELOCK)
        );
        vm.prank(writer);
        (bool recordOk,) = recordTo.call(recordData);
        assertTrue(recordOk, "direct record");

        assertEq(LibStoxMigrations.applied(writer, LibStoxMigrations.GOVERNANCE_TIMELOCK), 1_791_056_759);
        assertEq(LibStoxMigrations.applied(writer, LibStoxMigrations.ORCHESTRATOR_EMERGENCY), 1_800_000_000);
        assertEq(LibStoxMigrations.head(writer), LibStoxMigrations.ORCHESTRATOR_EMERGENCY);
        assertEq(LibStoxMigrations.applied(makeAddr("other"), LibStoxMigrations.ORCHESTRATOR_EMERGENCY), 0);
    }

    /// @notice The call names its writer, so an account the writer never
    /// approved cannot send it.
    function testCallSentByAnotherAccountIsRefused() external {
        etchRegistry();
        address writer = makeAddr("writer");
        address other = makeAddr("other");
        (address to, bytes memory data) = LibStoxMigrations.applyMigrationCall(
            writer, LibStoxMigrations.ORCHESTRATOR_EMERGENCY, LibStoxMigrations.onto(writer, MIGRATION_HEAD_GENESIS)
        );

        vm.prank(other);
        (bool ok, bytes memory reason) = to.call(data);
        assertFalse(ok, "sent by another account");
        assertEq(
            reason,
            abi.encodeWithSelector(
                IMigrationRegistryV3.NotApproved.selector, writer, LibStoxMigrations.NAMESPACE, other
            )
        );
        assertEq(LibStoxMigrations.head(writer), MIGRATION_HEAD_GENESIS);
    }
}
