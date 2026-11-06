// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistry.sol";
import {IMigrationRegistryV5, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {IRegistryDelegatesV3} from "rain-deploy-0.1.30/src/interface/IRegistryDelegatesV3.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {
    RUNTIME_CODE as MIGRATION_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.30/src/generated/candidate/MigrationRegistry.sol";

import {LibOrchestratorInvariants} from "../../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {ScriptDeclaration} from "../../../src/interface/IStoxScript.sol";
import {LibStoxMigrations, NoGovernanceTimelockMigrationOnChain} from "../../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibStoxMigrationsHarness} from "./LibStoxMigrationsHarness.sol";
import {LibTestPreBackfillFork} from "../../lib/LibTestPreBackfillFork.sol";

/// @title LibStoxMigrationsTest
/// @notice The pinned execution moment of the governance-timelock migration is the chain's own record of
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
            0xd708186f68D527B64c001398550627508205EE31,
            "st0x.deploy migration records live at this registry instance; moving it strands them"
        );
        assertEq(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
            0x98c1c8681edccad8869a2f156966c8d0042582a17adb2946de13395b42630603,
            "st0x.deploy migration records live at this registry instance; moving it strands them"
        );
    }

    function testNamespace() external pure {
        assertEq(LibStoxMigrations.NAMESPACE, keccak256("st0x.deploy"));
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

    function assertExecution(SupportedNetwork memory network) internal {
        (uint256 appliedAt, uint256 blockNumber) = LibStoxMigrations.governanceTimelockExecution(network.chainId);
        vm.createSelectFork(network.name, blockNumber);
        assertEq(block.chainid, network.chainId, network.name);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);

        bytes32[] memory topics = new bytes32[](3);
        topics[0] = keccak256("OwnershipTransferred(address,address)");
        topics[1] = bytes32(uint256(uint160(safe)));
        topics[2] = bytes32(uint256(uint160(timelock)));
        Vm.EthGetLogs[] memory logs =
            vm.eth_getLogs(blockNumber, blockNumber, LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON, topics);
        assertEq(logs.length, 1, string.concat(network.name, ": ownership transfers in the pinned block"));
        assertEq(block.timestamp, appliedAt, string.concat(network.name, ": timestamp"));

        LibTestPreBackfillFork.select(vm, network.name);
        LibMigrationRegistry.checkCodeHash();
    }

    /// @notice Every network ST0x deploys to has a pinned execution moment,
    /// and it is the chain's own record of the migration.
    function testGovernanceTimelockExecutionOnEveryDeploymentNetwork() external {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 i = 0; i < networks.length; i++) {
            assertExecution(networks[i]);
        }
    }

    function etchRegistry() internal {
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, MIGRATION_REGISTRY_RUNTIME_CODE);
    }

    function testRecordCallWritesTheDeclarationOnTheRootLine(bytes32 id, bytes32 head, bool history) external {
        etchRegistry();
        (address to, bytes memory data) =
            LibStoxMigrations.recordCall(ScriptDeclaration({id: id, onto: head, history: history}));

        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(
            data,
            abi.encodeCall(
                IMigrationRegistryV5.applyMigrationV5,
                (
                    LibRegistryAuthority.ROOT_AUTHORITY,
                    LibStoxMigrations.NAMESPACE,
                    id,
                    LibMigrationRegistry.onto(LibRegistryAuthority.ROOT_AUTHORITY, LibStoxMigrations.NAMESPACE, head),
                    ""
                )
            )
        );
    }

    function testHistoryCallWritesTheDeclarationOnTheRootLineAtTheMoment(
        bytes32 id,
        bytes32 head,
        bool history,
        uint256 appliedAt
    ) external {
        etchRegistry();
        (address to, bytes memory data) =
            LibStoxMigrations.historyCall(ScriptDeclaration({id: id, onto: head, history: history}), appliedAt);

        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(
            data,
            abi.encodeCall(
                IMigrationRegistryV5.applyMigrationHistoryV5,
                (
                    LibRegistryAuthority.ROOT_AUTHORITY,
                    LibStoxMigrations.NAMESPACE,
                    id,
                    appliedAt,
                    LibMigrationRegistry.onto(LibRegistryAuthority.ROOT_AUTHORITY, LibStoxMigrations.NAMESPACE, head),
                    ""
                )
            )
        );
    }

    function externalRecordCall(ScriptDeclaration memory declared) external view returns (address, bytes memory) {
        return LibStoxMigrations.recordCall(declared);
    }

    function externalHistoryCall(ScriptDeclaration memory declared, uint256 appliedAt)
        external
        view
        returns (address, bytes memory)
    {
        return LibStoxMigrations.historyCall(declared, appliedAt);
    }

    function testCallsRefuseARegistryThatIsNotThePinnedCode() external {
        ScriptDeclaration memory declared =
            ScriptDeclaration({id: LibStoxMigrations.MULTISIG_THRESHOLD, onto: MIGRATION_HEAD_GENESIS, history: true});
        bytes memory reason = abi.encodeWithSelector(
            LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.codehash
        );
        vm.expectRevert(reason);
        this.externalRecordCall(declared);
        vm.expectRevert(reason);
        this.externalHistoryCall(declared, 1);
    }

    /// @notice The Safe is an unscoped delegate of the root, so what it sends
    /// lands on the root line: the history record at its moment, the direct
    /// record at its block, the head at the latest.
    function testCallsSentByARootDelegateLandOnTheRootLine() external {
        etchRegistry();
        vm.warp(1_800_000_000);
        address safe = makeAddr("safe");
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        IRegistryDelegatesV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS).approveUnscopedV5(safe);
        assertEq(LibStoxMigrations.head(), MIGRATION_HEAD_GENESIS);

        (address historyTo, bytes memory historyData) = LibStoxMigrations.historyCall(
            ScriptDeclaration({id: LibStoxMigrations.MULTISIG_THRESHOLD, onto: MIGRATION_HEAD_GENESIS, history: true}),
            1_782_241_221
        );
        vm.prank(safe);
        (bool historyOk,) = historyTo.call(historyData);
        assertTrue(historyOk, "history record");
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.MULTISIG_THRESHOLD);

        (address recordTo, bytes memory recordData) = LibStoxMigrations.recordCall(
            ScriptDeclaration({
                id: LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5,
                onto: LibStoxMigrations.MULTISIG_THRESHOLD,
                history: false
            })
        );
        vm.prank(safe);
        (bool recordOk,) = recordTo.call(recordData);
        assertTrue(recordOk, "direct record");

        assertEq(LibStoxMigrations.applied(LibStoxMigrations.MULTISIG_THRESHOLD), 1_782_241_221);
        assertEq(LibStoxMigrations.applied(LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5), 1_800_000_000);
        assertEq(LibStoxMigrations.applied(LibStoxMigrations.GOVERNANCE_TIMELOCK), 0);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5);
        assertEq(
            LibMigrationRegistry.appliedOntoV5(
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxMigrations.NAMESPACE,
                LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5
            ),
            LibStoxMigrations.MULTISIG_THRESHOLD
        );
    }

    function testCallSentByAnAccountTheRootNeverApprovedIsRefused() external {
        etchRegistry();
        address other = makeAddr("other");
        (address to, bytes memory data) = LibStoxMigrations.recordCall(
            ScriptDeclaration({id: LibStoxMigrations.MULTISIG_THRESHOLD, onto: MIGRATION_HEAD_GENESIS, history: false})
        );

        vm.prank(other);
        (bool ok, bytes memory reason) = to.call(data);
        assertFalse(ok, "sent by another account");
        assertEq(
            reason,
            abi.encodeWithSelector(
                IRegistryDelegatesV3.NotApproved.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxMigrations.NAMESPACE,
                other
            )
        );
        assertEq(LibStoxMigrations.head(), MIGRATION_HEAD_GENESIS);
    }
}
