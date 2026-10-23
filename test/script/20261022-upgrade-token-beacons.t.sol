// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV3} from "rain-deploy-0.1.22/src/interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.22/src/lib/LibMigrationRegistryDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.22/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.22/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.22/src/lib/LibSafeTxBuilderJson.sol";

import {
    CandidateNotDeployed,
    TimelockNotApprovedWriter,
    UnexpectedMigrationLine
} from "../../script/20261022-upgrade-token-beacons.s.sol";
import {UpgradeTokenBeaconsHarness} from "./UpgradeTokenBeaconsHarness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {ST0xOrchestrator} from "../../src/concrete/ST0xOrchestrator.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @notice The beacon upgrade is required on this chain and its record is
/// not on chain. Schedule it, then execute it after the delay.
/// @param network The chain still pending.
error TokenBeaconsUpgradeNotApplied(string network);

/// @title UpgradeTokenBeaconsTest
/// @notice The upgrade on every deployment network at head, in two parts per
/// network. The bundle: while the chain has not executed it, the fork is
/// brought to the state it is scheduled from (the root authority's
/// delegates approved, the orchestrator admin move executed, the candidates
/// deployed), `run()` schedules and proves it and writes the artifact,
/// `verify` accepts that artifact, and the artifact executed by the owners
/// leaves the operation pending; once executed on chain, the chain must serve
/// the candidates. The requirement: the upgrade's record is on chain, red
/// until it is.
contract UpgradeTokenBeaconsTest is Test {
    bytes32 internal constant TOKEN_BEACONS_UPGRADE = keccak256("script/20261022-upgrade-token-beacons.s.sol");

    /// @notice The root authority's approval of `delegate` as a writer of this
    /// repo's line, on the fork, where the chain does not carry it yet.
    function approve(address delegate) internal {
        if (!LibStoxMigrations.approved(delegate)) {
            vm.prank(LibStoxMigrations.WRITER);
            IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
                .approveV3(LibStoxMigrations.NAMESPACE, delegate);
        }
    }

    /// @notice The orchestrator admin move this upgrade is applied after,
    /// executed on the fork where the chain has not.
    function executeOrchestratorMigrations(address safe) internal {
        if (LibStoxMigrations.applied(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) == 0) {
            OrchestratorAdminToTimelockHarness move = new OrchestratorAdminToTimelockHarness("upgrade-prerequisite");
            LibSafeFork.executeBundle(vm, Safe(payable(safe)), move.callAuthorBundle());
        }
    }

    /// @notice The candidates, deployed on the fork where the chain has not:
    /// the facet the vault delegates to, then the vault, receipt and
    /// orchestrator.
    function deployCandidates() internal {
        LibRainDeploy.etchZoltuFactory(vm);
        bytes[4] memory creationCodes = [
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CREATION_CODE_CANDIDATE,
            LibProdDeployV4.STOX_RECEIPT_VAULT_CREATION_CODE_CANDIDATE,
            LibProdDeployV4.STOX_RECEIPT_CREATION_CODE_CANDIDATE,
            LibProdDeployV4.ST0X_ORCHESTRATOR_CREATION_CODE_CANDIDATE
        ];
        address[4] memory addresses = [
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE,
            LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE,
            LibProdDeployV4.STOX_RECEIPT_CANDIDATE,
            LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE
        ];
        for (uint256 i = 0; i < creationCodes.length; i++) {
            if (addresses[i].code.length == 0) {
                assertEq(LibRainDeploy.deployZoltu(creationCodes[i]), addresses[i], "candidate address");
            }
        }
    }

    /// @notice The fork in the state the upgrade is scheduled from.
    function prepare() internal {
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        approve(safe);
        approve(LibTimelockInvariants.timelockForChainId(block.chainid));
        executeOrchestratorMigrations(safe);
        deployCandidates();
    }

    function assertBundle(string memory network) internal {
        vm.createSelectFork(network);
        UpgradeTokenBeaconsHarness script = new UpgradeTokenBeaconsHarness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);

        if (LibStoxMigrations.applied(TOKEN_BEACONS_UPGRADE) != 0) {
            console2.log(string.concat("EXECUTED [", network, "]: asserting the upgraded state"));
            address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
            assertEq(
                IBeacon(beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]).implementation(),
                LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE
            );
            assertEq(
                IBeacon(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX]).implementation(),
                LibProdDeployV4.STOX_RECEIPT_CANDIDATE
            );
            assertEq(
                IBeacon(beacons[LibBeaconInvariants.ORCHESTRATOR_BEACON_INDEX]).implementation(),
                LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE
            );
            vm.expectPartialRevert(UnexpectedMigrationLine.selector);
            script.callPreflight();
            return;
        }

        console2.log(string.concat("PENDING [", network, "]: scheduling, verifying and executing the upgrade"));
        prepare();
        uint256 preRun = vm.snapshotState();
        script.run();
        vm.revertToState(preRun);

        string memory artifactPath = script.callArtifactPath();
        script.verify(artifactPath);

        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, safe, "artifact Safe");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        TimelockController controller =
            TimelockController(payable(LibTimelockInvariants.timelockForChainId(block.chainid)));
        bytes32 id = script.callOperationId();
        assertTrue(controller.isOperationPending(id), "scheduled");
        assertFalse(controller.isOperationReady(id), "not ready inside the delay");
        assertEq(
            controller.getTimestamp(id),
            block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY,
            "ready at the delay"
        );
    }

    function assertApplied(string memory network) internal {
        vm.createSelectFork(network);
        if (LibStoxMigrations.applied(TOKEN_BEACONS_UPGRADE) == 0) {
            revert TokenBeaconsUpgradeNotApplied(network);
        }
    }

    function testUpgradeBundleBase() external {
        assertBundle(LibRainDeploy.BASE);
    }

    function testUpgradeBundleEthereum() external {
        assertBundle(LibStoxDeployNetworks.ETHEREUM);
    }

    function testUpgradeBundleHyperEvm() external {
        assertBundle(LibStoxDeployNetworks.HYPEREVM);
    }

    function testUpgradeBundleRobinhood() external {
        assertBundle(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testUpgradeBundleBsc() external {
        assertBundle(LibStoxDeployNetworks.BSC);
    }

    function testUpgradeAppliedBase() external {
        assertApplied(LibRainDeploy.BASE);
    }

    function testUpgradeAppliedEthereum() external {
        assertApplied(LibStoxDeployNetworks.ETHEREUM);
    }

    function testUpgradeAppliedHyperEvm() external {
        assertApplied(LibStoxDeployNetworks.HYPEREVM);
    }

    function testUpgradeAppliedRobinhood() external {
        assertApplied(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testUpgradeAppliedBsc() external {
        assertApplied(LibStoxDeployNetworks.BSC);
    }

    /// @notice Whether the upgrade has executed on the active chain. The
    /// refusal tests need the pre-upgrade state; once it has executed they
    /// report SPENT and stop asserting.
    function spent() internal view returns (bool) {
        if (LibStoxMigrations.applied(TOKEN_BEACONS_UPGRADE) != 0) {
            console2.log("SPENT: the upgrade has executed on this chain");
            return true;
        }
        return false;
    }

    /// @notice Scheduling before the orchestrator admin move is refused: the
    /// batch's record could never apply onto the line.
    function testRefusesBeforeTheAdminMove() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (spent()) return;
        if (LibStoxMigrations.applied(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) != 0) return;
        UpgradeTokenBeaconsHarness script = new UpgradeTokenBeaconsHarness("before-admin-move");
        deployCandidates();
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, LibStoxMigrations.head()));
        script.callPreflight();
    }

    /// @notice A timelock the root authority has not approved is refused: the
    /// batch's record would revert at execution, after the delay.
    function testRefusesUnapprovedTimelock() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (spent()) return;
        UpgradeTokenBeaconsHarness script = new UpgradeTokenBeaconsHarness("unapproved-timelock");
        prepare();
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.prank(LibStoxMigrations.WRITER);
        IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .revokeV3(LibStoxMigrations.NAMESPACE, timelock);
        vm.expectRevert(abi.encodeWithSelector(TimelockNotApprovedWriter.selector, timelock));
        script.callPreflight();
    }

    /// @notice A candidate missing from the chain is refused before anything
    /// is scheduled onto it.
    function testRefusesMissingCandidate() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (spent()) return;
        UpgradeTokenBeaconsHarness script = new UpgradeTokenBeaconsHarness("missing-candidate");
        prepare();
        vm.etch(LibProdDeployV4.STOX_RECEIPT_CANDIDATE, "");
        vm.expectRevert(
            abi.encodeWithSelector(
                CandidateNotDeployed.selector,
                LibProdDeployV4.STOX_RECEIPT_CANDIDATE,
                LibProdDeployV4.STOX_RECEIPT_CODEHASH_CANDIDATE,
                bytes32(0)
            )
        );
        script.callPreflight();
    }

    /// @notice The scheduled batch upgrades exactly the active chain's three
    /// beacons onto the three candidates and records the upgrade last.
    function testBatchShape() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        UpgradeTokenBeaconsHarness script = new UpgradeTokenBeaconsHarness("shape");
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = script.callBatch();
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        assertEq(targets.length, 4);
        assertEq(targets[0], beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]);
        assertEq(targets[1], beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX]);
        assertEq(targets[2], beacons[LibBeaconInvariants.ORCHESTRATOR_BEACON_INDEX]);
        assertEq(targets[3], LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        for (uint256 i = 0; i < values.length; i++) {
            assertEq(values[i], 0);
        }
        assertEq(
            payloads[0], abi.encodeWithSignature("upgradeTo(address)", LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE)
        );
        assertEq(payloads[1], abi.encodeWithSignature("upgradeTo(address)", LibProdDeployV4.STOX_RECEIPT_CANDIDATE));
        assertEq(
            payloads[2], abi.encodeWithSignature("upgradeTo(address)", LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE)
        );
        assertEq(
            payloads[3],
            abi.encodeCall(
                IMigrationRegistryV3.applyMigrationV3,
                (
                    LibStoxMigrations.WRITER,
                    LibStoxMigrations.NAMESPACE,
                    TOKEN_BEACONS_UPGRADE,
                    LibStoxMigrations.onto(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK)
                )
            )
        );
    }
}
