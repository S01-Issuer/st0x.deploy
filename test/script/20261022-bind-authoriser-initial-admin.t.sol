// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {LibSafe} from "rain-deploy-0.1.30/src/lib/LibSafe.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {IMigrationRegistryV5} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.30/src/lib/LibSafeTxBuilderJson.sol";

import {
    AuthoriserInitialAdminBindingMismatch,
    BindAuthoriserInitialAdminRecordMismatch,
    BindAuthoriserInitialAdminUnexpectedLine,
    SafeNotAuthoriserInitialAdminDelegate,
    bindAuthoriserInitialAdminDeclaration
} from "../../script/20261022-bind-authoriser-initial-admin.s.sol";
import {migrateMultisigThresholdDeclaration} from "../../script/20260619-migrate-multisig-threshold.s.sol";
import {BindAuthoriserInitialAdminHarness} from "./BindAuthoriserInitialAdminHarness.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {GrantOrchestratorEmergencyHarness} from "./GrantOrchestratorEmergencyHarness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @dev A Safe line write past the bind.
bytes32 constant LATER = keccak256("later");

/// @title BindAuthoriserInitialAdminTest
/// @notice The bind on every deployment network at head, with every
/// predecessor on the Safe's line and the root's approval of the Safe written
/// on the fork where the chain lacks them.
contract BindAuthoriserInitialAdminTest is Test {
    IConfigRegistryV5 internal constant CONFIG_REGISTRY =
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);

    /// @dev Applies every predecessor before the threshold migration that the
    /// chain lacks.
    function advanceToOrchestratorAdminMove(address safe, string memory tag) internal {
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) == 0) {
            LibSafeFork.executeBundle(
                vm, Safe(payable(safe)), new GrantOrchestratorEmergencyHarness().callAuthorBundle()
            );
        }
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5) == 0) {
            LibSafeFork.executeBundle(
                vm, Safe(payable(safe)), new BackfillMigrationRegistryV5Harness(tag).callAuthorBundle()
            );
        }
        if (LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) == 0) {
            LibSafeFork.executeBundle(
                vm, Safe(payable(safe)), new OrchestratorAdminToTimelockHarness(tag).callAuthorBundle()
            );
        }
    }

    /// @dev Applies every predecessor on the Safe's line that the chain lacks.
    function advanceLine(address safe, string memory tag) internal {
        advanceToOrchestratorAdminMove(safe, tag);
        if (LibStoxMigrations.applied(safe, migrateMultisigThresholdDeclaration().id) == 0) {
            (address to, bytes memory data) = LibStoxMigrations.recordCall(
                migrateMultisigThresholdDeclaration(), safe, LibTimelockInvariants.timelockForChainId(block.chainid)
            );
            LibSafeFork.simulateCall(vm, Safe(payable(safe)), to, data);
        }
    }

    function approved(address safe) internal view returns (bool) {
        return CONFIG_REGISTRY.approvedV5(
            LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME, safe
        );
    }

    /// @dev The root approves the Safe where the chain lacks the approval.
    function approveSafe(address safe) internal {
        if (!approved(safe)) {
            vm.prank(LibStoxConfig.ROOT_AUTHORITY);
            CONFIG_REGISTRY.approveV5(LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME, safe);
        }
    }

    function assertBundle(string memory network) internal {
        vm.createSelectFork(network);
        BindAuthoriserInitialAdminHarness script = new BindAuthoriserInitialAdminHarness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        bytes32 id = bindAuthoriserInitialAdminDeclaration().id;

        if (LibStoxMigrations.applied(safe, id) != 0) {
            console2.log(string.concat("EXECUTED [", network, "]: asserting the binding"));
            assertEq(LibStoxConfig.authoriserInitialAdmin(), timelock, "bound admin");
            vm.expectPartialRevert(BindAuthoriserInitialAdminUnexpectedLine.selector);
            script.callPreflight();
            return;
        }

        console2.log(string.concat("PENDING [", network, "]: authoring, verifying and executing the bind"));
        advanceLine(safe, network);
        approveSafe(safe);

        uint256 preRun = vm.snapshotState();
        script.run();
        vm.revertToState(preRun);

        string memory artifactPath = script.callArtifactPath();
        script.verify(artifactPath);

        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, safe, "artifact Safe");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        assertEq(LibStoxConfig.authoriserInitialAdmin(), timelock, "bound admin");
        assertEq(LibStoxMigrations.applied(safe, id), block.timestamp, "record moment");
        assertEq(LibStoxMigrations.head(safe), id, "line head");

        vm.expectRevert(abi.encodeWithSelector(BindAuthoriserInitialAdminUnexpectedLine.selector, id));
        script.callPreflight();
    }

    /// @dev A HyperEVM fork just before the bind, or false once the bind has
    /// executed on chain.
    function readyOnFork(string memory tag)
        internal
        returns (BindAuthoriserInitialAdminHarness script, address safe, bool ready)
    {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        script = new BindAuthoriserInitialAdminHarness(tag);
        safe = LibSafeInvariants.safeForChainId(block.chainid);
        ready = LibStoxMigrations.applied(safe, bindAuthoriserInitialAdminDeclaration().id) == 0;
        if (!ready) console2.log("SPENT: the bind has executed on this chain");
    }

    function executedOnFork(string memory tag)
        internal
        returns (BindAuthoriserInitialAdminHarness script, address safe, bool ready)
    {
        (script, safe, ready) = readyOnFork(tag);
        if (!ready) return (script, safe, ready);
        advanceLine(safe, tag);
        approveSafe(safe);
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        script.callAssertPostState();
    }

    function testPreflightRefusesAnUnapprovedSafe() external {
        (BindAuthoriserInitialAdminHarness script, address safe, bool ready) = readyOnFork("unapproved");
        if (!ready) return;
        advanceLine(safe, "unapproved");
        if (approved(safe)) {
            vm.prank(LibStoxConfig.ROOT_AUTHORITY);
            CONFIG_REGISTRY.revokeV5(LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME, safe);
        }
        vm.expectRevert(abi.encodeWithSelector(SafeNotAuthoriserInitialAdminDelegate.selector, safe));
        script.callPreflight();
    }

    function testPreflightRefusesALineBeforeTheThresholdMigration() external {
        (BindAuthoriserInitialAdminHarness script, address safe, bool ready) = readyOnFork("early");
        if (!ready) return;
        if (LibStoxMigrations.applied(safe, migrateMultisigThresholdDeclaration().id) != 0) return;
        advanceToOrchestratorAdminMove(safe, "early");
        approveSafe(safe);
        vm.expectRevert(
            abi.encodeWithSelector(
                BindAuthoriserInitialAdminUnexpectedLine.selector, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK
            )
        );
        script.callPreflight();
    }

    function testPreflightRefusesALinePastTheThresholdMigration() external {
        (BindAuthoriserInitialAdminHarness script, address safe, bool ready) = readyOnFork("past");
        if (!ready) return;
        advanceLine(safe, "past");
        approveSafe(safe);
        vm.prank(safe);
        IMigrationRegistryV5(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigrationV5(
                safe,
                LibStoxMigrations.NAMESPACE,
                LATER,
                LibStoxMigrations.onto(safe, migrateMultisigThresholdDeclaration().id),
                ""
            );
        vm.expectRevert(abi.encodeWithSelector(BindAuthoriserInitialAdminUnexpectedLine.selector, LATER));
        script.callPreflight();
    }

    function testPostStateRefusesAnotherAdmin() external {
        address other = address(0xBEEF);
        (BindAuthoriserInitialAdminHarness script,, bool ready) = executedOnFork("other-admin");
        if (!ready) return;
        vm.warp(block.timestamp + 1);
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        CONFIG_REGISTRY.registerV5(
            LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME, "address", abi.encode(other), ""
        );
        vm.expectRevert(
            abi.encodeWithSelector(AuthoriserInitialAdminBindingMismatch.selector, abi.encode(other), block.timestamp)
        );
        script.callAssertPostState();
    }

    function testPostStateRefusesABindingFromAnotherBlock() external {
        (BindAuthoriserInitialAdminHarness script,, bool ready) = executedOnFork("binding-block");
        if (!ready) return;
        uint256 boundAt = block.timestamp;
        vm.warp(boundAt + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthoriserInitialAdminBindingMismatch.selector,
                abi.encode(LibTimelockInvariants.timelockForChainId(block.chainid)),
                boundAt
            )
        );
        script.callAssertPostState();
    }

    function testPostStateRefusesARecordFromAnotherBlock() external {
        (BindAuthoriserInitialAdminHarness script,, bool ready) = executedOnFork("record-block");
        if (!ready) return;
        uint256 recordedAt = block.timestamp;
        vm.warp(recordedAt + 1);
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        CONFIG_REGISTRY.registerV5(
            LibStoxConfig.ROOT_AUTHORITY,
            LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME,
            "address",
            abi.encode(LibTimelockInvariants.timelockForChainId(block.chainid)),
            ""
        );
        vm.expectRevert(abi.encodeWithSelector(BindAuthoriserInitialAdminRecordMismatch.selector, recordedAt));
        script.callAssertPostState();
    }

    function testPostStateRefusesALineThatDoesNotEndAtTheRecord() external {
        (BindAuthoriserInitialAdminHarness script, address safe, bool ready) = executedOnFork("line");
        if (!ready) return;
        vm.prank(safe);
        IMigrationRegistryV5(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigrationV5(
                safe,
                LibStoxMigrations.NAMESPACE,
                LATER,
                LibStoxMigrations.onto(safe, bindAuthoriserInitialAdminDeclaration().id),
                ""
            );
        vm.expectRevert(abi.encodeWithSelector(BindAuthoriserInitialAdminUnexpectedLine.selector, LATER));
        script.callAssertPostState();
    }

    function testPostStateRefusesADriftedSafe() external {
        (BindAuthoriserInitialAdminHarness script, address safe, bool ready) = executedOnFork("drifted");
        if (!ready) return;
        vm.mockCall(safe, abi.encodeCall(OwnerManager.getThreshold, ()), abi.encode(uint256(4)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector, safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD, 4
            )
        );
        script.callAssertPostState();
    }

    function testBindBundleBase() external {
        assertBundle(LibRainDeploy.BASE);
    }

    function testBindBundleEthereum() external {
        assertBundle(LibStoxDeployNetworks.ETHEREUM);
    }

    function testBindBundleHyperEvm() external {
        assertBundle(LibStoxDeployNetworks.HYPEREVM);
    }

    function testBindBundleRobinhood() external {
        assertBundle(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testBindBundleBsc() external {
        assertBundle(LibStoxDeployNetworks.BSC);
    }
}
