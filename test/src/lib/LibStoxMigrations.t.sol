// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.38/src/lib/LibMigrationRegistry.sol";
import {IMigrationRegistryV5, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.38/src/interface/IMigrationRegistryV5.sol";
import {IRegistryDelegatesV3} from "rain-deploy-0.1.38/src/interface/IRegistryDelegatesV3.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.38/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.38/src/lib/LibRegistryAuthority.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {
    RUNTIME_CODE as MIGRATION_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.38/src/generated/candidate/MigrationRegistry.sol";

import {LibOrchestratorInvariants} from "../../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {ScriptDeclaration} from "../../../src/interface/IStoxScript.sol";
import {
    LibStoxMigrations,
    NoGovernanceTimelockMigrationOnChain,
    SafeNotApprovedWriter
} from "../../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibStoxMigrationsHarness} from "./LibStoxMigrationsHarness.sol";
import {LibTestPreBackfillFork} from "../../lib/LibTestPreBackfillFork.sol";
import {LibTestRootLine} from "../../lib/LibTestRootLine.sol";

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

    /// @notice The chains with a root line are the deployment networks, in
    /// their order, 0G last.
    function testLineNetworksAreTheDeploymentNetworks() external pure {
        SupportedNetwork[] memory deployed =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        SupportedNetwork[] memory lines = LibStoxMigrations.lineNetworks();
        assertEq(lines.length, deployed.length);
        for (uint256 i = 0; i < deployed.length; i++) {
            assertEq(lines[i].name, deployed[i].name);
            assertEq(lines[i].chainId, deployed[i].chainId);
        }
        assertEq(lines[deployed.length - 1].name, LibStoxDeployNetworks.ZEROG);
        assertEq(lines[deployed.length - 1].chainId, LibSafeInvariants.ZEROG_CHAIN_ID);
    }

    /// @notice Only 0G joined after the backfilled history ran everywhere else.
    function testOnlyZerogIsWithoutHistory(uint256 chainId) external pure {
        assertEq(LibStoxMigrations.withoutHistory(chainId), chainId == LibSafeInvariants.ZEROG_CHAIN_ID);
        assertTrue(LibStoxMigrations.withoutHistory(LibSafeInvariants.ZEROG_CHAIN_ID));
        SupportedNetwork[] memory deployed =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.networksBeforeZerog());
        for (uint256 i = 0; i < deployed.length; i++) {
            assertFalse(LibStoxMigrations.withoutHistory(deployed[i].chainId), deployed[i].name);
        }
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

    /// @notice Every network ST0x deployed to before 0G has a pinned execution
    /// moment, and it is the chain's own record of the migration. 0G ran none
    /// of it: its line holds the record record-only, with no moment.
    function testGovernanceTimelockExecutionOnEveryDeploymentNetwork() external {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.networksBeforeZerog());
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

    function testRecordOnlyBundleIsTheRecordCallAlone(bytes32 id, bytes32 head, bool history) external {
        etchRegistry();
        SafeTx[] memory txs =
            LibStoxMigrations.recordOnlyBundle(ScriptDeclaration({id: id, onto: head, history: history}));

        assertEq(txs.length, 1, "one transaction");
        assertEq(txs[0].to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, "registry");
        assertEq(txs[0].value, 0, "value");
        assertEq(uint8(txs[0].operation), uint8(Enum.Operation.Call), "operation");
        assertEq(
            txs[0].data,
            abi.encodeCall(
                IMigrationRegistryV5.applyMigrationV5,
                (
                    LibRegistryAuthority.ROOT_AUTHORITY,
                    LibStoxMigrations.NAMESPACE,
                    id,
                    LibMigrationRegistry.onto(LibRegistryAuthority.ROOT_AUTHORITY, LibStoxMigrations.NAMESPACE, head),
                    ""
                )
            ),
            "record calldata"
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

    function genesisNext() internal pure returns (ScriptDeclaration memory) {
        return
            ScriptDeclaration({id: LibStoxMigrations.MULTISIG_THRESHOLD, onto: MIGRATION_HEAD_GENESIS, history: false});
    }

    /// @dev `approved`, `assertNext` and the registry's own write check all
    /// give `writes` for `delegate`.
    function assertRootLineWriter(address delegate, bool writes) internal {
        assertEq(LibStoxMigrations.approved(delegate), writes, "approved");
        LibStoxMigrationsHarness ext = new LibStoxMigrationsHarness();
        if (!writes) vm.expectRevert(abi.encodeWithSelector(SafeNotApprovedWriter.selector, delegate));
        ext.assertNext(genesisNext(), delegate);
        (address to, bytes memory data) = LibStoxMigrations.recordCall(genesisNext());
        vm.prank(delegate);
        (bool ok,) = to.call(data);
        assertEq(ok, writes, "registry write");
    }

    function testADelegateForTheNamespaceAloneWritesTheRootLine() external {
        etchRegistry();
        address delegate = makeAddr("delegate");
        LibTestRootLine.approveScope(vm, LibStoxMigrations.NAMESPACE, delegate);
        assertRootLineWriter(delegate, true);
    }

    function testADelegateForAnotherScopeIsRefused(bytes32 scope) external {
        vm.assume(scope != LibStoxMigrations.NAMESPACE && scope != bytes32(0));
        etchRegistry();
        address delegate = makeAddr("delegate");
        LibTestRootLine.approveScope(vm, scope, delegate);
        assertRootLineWriter(delegate, false);
    }

    function testAnUnscopedDelegateWritesTheRootLine() external {
        etchRegistry();
        address delegate = makeAddr("delegate");
        LibTestRootLine.approve(vm, delegate);
        assertRootLineWriter(delegate, true);
    }

    function testTheRootAuthorityWritesTheRootLine() external {
        etchRegistry();
        assertRootLineWriter(LibRegistryAuthority.ROOT_AUTHORITY, true);
    }

    function testARevokedNamespaceDelegateIsRefused() external {
        etchRegistry();
        address delegate = makeAddr("delegate");
        LibTestRootLine.approveScope(vm, LibStoxMigrations.NAMESPACE, delegate);
        LibTestRootLine.revokeScope(vm, LibStoxMigrations.NAMESPACE, delegate);
        assertRootLineWriter(delegate, false);
    }

    function testARevokedUnscopedDelegateIsRefused() external {
        etchRegistry();
        address delegate = makeAddr("delegate");
        LibTestRootLine.approve(vm, delegate);
        LibTestRootLine.revokeUnscoped(vm, delegate);
        assertRootLineWriter(delegate, false);
    }

    function testADelegateOfAnotherAccountIsRefused() external {
        etchRegistry();
        address delegate = makeAddr("delegate");
        IRegistryDelegatesV3 registry =
            IRegistryDelegatesV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        vm.startPrank(makeAddr("other"));
        registry.approveV5(LibStoxMigrations.NAMESPACE, delegate);
        registry.approveUnscopedV5(delegate);
        vm.stopPrank();
        assertRootLineWriter(delegate, false);
    }
}
