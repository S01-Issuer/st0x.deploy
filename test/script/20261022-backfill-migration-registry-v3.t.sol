// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.21/src/lib/LibRainDeploy.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.21/src/interface/IMigrationRegistryV3.sol";
import {IMigrationRegistryV2} from "rain-deploy-0.1.21/src/interface/deprecated/IMigrationRegistryV2.sol";
import {DEPLOYED_ADDRESS as REGISTRY_V2} from "rain-deploy-0.1.21/src/generated/0_1_18/MigrationRegistry.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.21/src/lib/LibMigrationRegistry.sol";
import {SafeTx} from "rain-deploy-0.1.21/src/lib/LibSafeTx.sol";
import {LibSafe} from "rain-deploy-0.1.21/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.21/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.21/src/lib/LibSafeTxBuilderJson.sol";
import {ITimelockControllerState, LibTimelockController} from "rain-deploy-0.1.21/src/lib/LibTimelockController.sol";

import {
    BackfillRecordMismatch,
    GovernanceTimelockMomentMismatch,
    UnexpectedRegistryV2CodeHash,
    UnexpectedRegistryV2Line,
    UnexpectedRegistryV2Order,
    UnexpectedRegistryV3Line
} from "../../script/20261022-backfill-migration-registry-v3.s.sol";
import {BackfillMigrationRegistryV3Harness} from "./BackfillMigrationRegistryV3Harness.sol";
import {LibOrchestratorInvariants, OrchestratorRoleMissing} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibRbacMigration} from "../../src/lib/LibRbacMigration.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @notice The Safe's V2 records are not yet in V3 on this chain. Execute the
/// backfill bundle.
/// @param network The chain still pending.
error BackfillNotApplied(string network);

/// @title BackfillMigrationRegistryV3Test
/// @notice Per network: the bundle carries every V2 record into V3 at its V2
/// moment and the invariants then hold; once executed the script refuses. The
/// requirement: the backfill is on chain, red until it is.
contract BackfillMigrationRegistryV3Test is Test {
    IMigrationRegistryV2 internal constant V2 = IMigrationRegistryV2(REGISTRY_V2);

    function assertCarried(address safe) internal view {
        bytes32 ns = LibStoxMigrations.NAMESPACE;
        bytes32 rbac = LibRbacMigration.STOX_RBAC_NAMESPACE;
        bytes32 eu = LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER;
        assertEq(
            LibStoxMigrations.applied(safe, LibStoxMigrations.GOVERNANCE_TIMELOCK),
            V2.applied(safe, ns, LibStoxMigrations.GOVERNANCE_TIMELOCK),
            "GOVERNANCE_TIMELOCK"
        );
        assertEq(
            LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY),
            V2.applied(safe, ns, LibStoxMigrations.ORCHESTRATOR_EMERGENCY),
            "ORCHESTRATOR_EMERGENCY"
        );
        assertEq(LibMigrationRegistry.appliedV3(safe, rbac, eu), V2.applied(safe, rbac, eu), "EU authoriser");
        assertTrue(LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) != 0, "emergency zero");
        assertTrue(LibMigrationRegistry.appliedV3(safe, rbac, eu) != 0, "EU zero");
        assertEq(
            LibMigrationRegistry.appliedOntoV3(safe, ns, LibStoxMigrations.ORCHESTRATOR_EMERGENCY),
            LibStoxMigrations.GOVERNANCE_TIMELOCK
        );
        assertEq(LibStoxMigrations.head(safe), LibStoxMigrations.ORCHESTRATOR_EMERGENCY);
        assertEq(LibMigrationRegistry.headV3(safe, rbac), eu);
        assertEq(LibMigrationRegistry.appliedByV3(safe, ns, LibStoxMigrations.ORCHESTRATOR_EMERGENCY), safe);
        LibOrchestratorInvariants.assertInstance(safe);
    }

    function assertBundle(string memory network) internal {
        vm.createSelectFork(network);
        BackfillMigrationRegistryV3Harness script = new BackfillMigrationRegistryV3Harness(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);

        if (LibStoxMigrations.head(safe) != MIGRATION_HEAD_GENESIS) {
            console2.log(string.concat("EXECUTED [", network, "]: asserting the backfilled state"));
            assertCarried(safe);
            vm.expectRevert(
                abi.encodeWithSelector(
                    UnexpectedRegistryV3Line.selector,
                    LibStoxMigrations.NAMESPACE,
                    LibStoxMigrations.ORCHESTRATOR_EMERGENCY
                )
            );
            script.callPreflight();
            return;
        }

        console2.log(string.concat("PENDING [", network, "]: authoring, verifying and executing the bundle"));
        uint256 preRun = vm.snapshotState();
        script.run();
        vm.revertToState(preRun);

        string memory artifactPath = script.callArtifactPath();
        script.verify(artifactPath);

        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, safe, "artifact Safe");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        assertCarried(safe);
        vm.expectRevert(
            abi.encodeWithSelector(
                UnexpectedRegistryV3Line.selector, LibStoxMigrations.NAMESPACE, LibStoxMigrations.ORCHESTRATOR_EMERGENCY
            )
        );
        script.callPreflight();
    }

    function assertApplied(string memory network) internal {
        vm.createSelectFork(network);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        if (
            LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) == 0
                || LibMigrationRegistry.appliedV3(
                        safe, LibRbacMigration.STOX_RBAC_NAMESPACE, LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER
                    ) == 0
        ) {
            revert BackfillNotApplied(network);
        }
    }

    function testBackfillBundleBase() external {
        assertBundle(LibRainDeploy.BASE);
    }

    function testBackfillBundleEthereum() external {
        assertBundle(LibStoxDeployNetworks.ETHEREUM);
    }

    function testBackfillBundleHyperEvm() external {
        assertBundle(LibStoxDeployNetworks.HYPEREVM);
    }

    function testBackfillBundleRobinhood() external {
        assertBundle(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testBackfillBundleBsc() external {
        assertBundle(LibStoxDeployNetworks.BSC);
    }

    function testBackfillAppliedBase() external {
        assertApplied(LibRainDeploy.BASE);
    }

    function testBackfillAppliedEthereum() external {
        assertApplied(LibStoxDeployNetworks.ETHEREUM);
    }

    function testBackfillAppliedHyperEvm() external {
        assertApplied(LibStoxDeployNetworks.HYPEREVM);
    }

    function testBackfillAppliedRobinhood() external {
        assertApplied(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testBackfillAppliedBsc() external {
        assertApplied(LibStoxDeployNetworks.BSC);
    }

    /// @notice The refusal tests need the pre-backfill state.
    function spent() internal view returns (bool) {
        if (LibStoxMigrations.head(LibSafeInvariants.safeForChainId(block.chainid)) != MIGRATION_HEAD_GENESIS) {
            console2.log("SPENT: the backfill has executed on this chain");
            return true;
        }
        return false;
    }

    function setUpBase() internal returns (BackfillMigrationRegistryV3Harness, address) {
        vm.createSelectFork(LibRainDeploy.BASE);
        return (new BackfillMigrationRegistryV3Harness("refusal"), LibSafeInvariants.safeForChainId(block.chainid));
    }

    function testRefusesUnpinnedRegistryV2Code() external {
        (BackfillMigrationRegistryV3Harness script,) = setUpBase();
        if (spent()) return;
        vm.etch(REGISTRY_V2, hex"00");
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRegistryV2CodeHash.selector, keccak256(hex"00")));
        script.callPreflight();
    }

    function testRefusesUnexpectedV2DeployHead() external {
        (BackfillMigrationRegistryV3Harness script, address safe) = setUpBase();
        if (spent()) return;
        bytes32 other = keccak256("some other migration");
        vm.mockCall(
            REGISTRY_V2,
            abi.encodeCall(IMigrationRegistryV2.head, (safe, LibStoxMigrations.NAMESPACE)),
            abi.encode(other)
        );
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRegistryV2Line.selector, LibStoxMigrations.NAMESPACE, other));
        script.callPreflight();
    }

    function testRefusesUnexpectedV2RbacHead() external {
        (BackfillMigrationRegistryV3Harness script, address safe) = setUpBase();
        if (spent()) return;
        bytes32 other = keccak256("some other migration");
        vm.mockCall(
            REGISTRY_V2,
            abi.encodeCall(IMigrationRegistryV2.head, (safe, LibRbacMigration.STOX_RBAC_NAMESPACE)),
            abi.encode(other)
        );
        vm.expectRevert(
            abi.encodeWithSelector(UnexpectedRegistryV2Line.selector, LibRbacMigration.STOX_RBAC_NAMESPACE, other)
        );
        script.callPreflight();
    }

    function testRefusesGovernanceTimelockMomentMismatch() external {
        (BackfillMigrationRegistryV3Harness script, address safe) = setUpBase();
        if (spent()) return;
        (uint256 pinned,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);
        vm.mockCall(
            REGISTRY_V2,
            abi.encodeCall(
                IMigrationRegistryV2.applied, (safe, LibStoxMigrations.NAMESPACE, LibStoxMigrations.GOVERNANCE_TIMELOCK)
            ),
            abi.encode(pinned + 1)
        );
        vm.expectRevert(abi.encodeWithSelector(GovernanceTimelockMomentMismatch.selector, pinned, pinned + 1));
        script.callPreflight();
    }

    function testRefusesUnexpectedV2Order() external {
        (BackfillMigrationRegistryV3Harness script, address safe) = setUpBase();
        if (spent()) return;
        vm.mockCall(
            REGISTRY_V2,
            abi.encodeCall(
                IMigrationRegistryV2.appliedOnto,
                (safe, LibStoxMigrations.NAMESPACE, LibStoxMigrations.ORCHESTRATOR_EMERGENCY)
            ),
            abi.encode(MIGRATION_HEAD_GENESIS)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                UnexpectedRegistryV2Order.selector, LibStoxMigrations.ORCHESTRATOR_EMERGENCY, MIGRATION_HEAD_GENESIS
            )
        );
        script.callAuthorBundle();
    }

    function testRefusesV3DeployLineOffGenesis() external {
        (BackfillMigrationRegistryV3Harness script, address safe) = setUpBase();
        if (spent()) return;
        bytes32 other = keccak256("some other migration");
        vm.prank(safe);
        LibMigrationRegistry.applyMigrationV3(
            safe, LibStoxMigrations.NAMESPACE, other, LibStoxMigrations.onto(safe, MIGRATION_HEAD_GENESIS)
        );
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRegistryV3Line.selector, LibStoxMigrations.NAMESPACE, other));
        script.callPreflight();
    }

    function testRefusesV3RbacLineOffGenesis() external {
        (BackfillMigrationRegistryV3Harness script, address safe) = setUpBase();
        if (spent()) return;
        bytes32 other = keccak256("some other migration");
        vm.prank(safe);
        LibMigrationRegistry.applyMigrationV3(
            safe,
            LibRbacMigration.STOX_RBAC_NAMESPACE,
            other,
            LibMigrationRegistry.onto(safe, LibRbacMigration.STOX_RBAC_NAMESPACE, MIGRATION_HEAD_GENESIS)
        );
        vm.expectRevert(
            abi.encodeWithSelector(UnexpectedRegistryV3Line.selector, LibRbacMigration.STOX_RBAC_NAMESPACE, other)
        );
        script.callPreflight();
    }

    function testVerifyRefusesTamperedArtifact() external {
        (BackfillMigrationRegistryV3Harness script, address safe) = setUpBase();
        if (spent()) return;
        string memory json =
            LibSafeTxBuilderJson.toJson(vm, safe, block.chainid, "tamper test", script.callAuthorBundle());
        string memory cleanPath =
            string.concat("out/20261022-backfill-migration-registry-v3-clean-", vm.toString(block.chainid), ".json");
        vm.writeFile(cleanPath, json);
        script.verify(cleanPath);
        uint256 euAt =
            V2.applied(safe, LibRbacMigration.STOX_RBAC_NAMESPACE, LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER);
        (, bytes memory euData) = LibMigrationRegistry.applyMigrationHistoryV3Call(
            safe,
            LibRbacMigration.STOX_RBAC_NAMESPACE,
            LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER,
            euAt,
            LibMigrationRegistry.onto(safe, LibRbacMigration.STOX_RBAC_NAMESPACE, MIGRATION_HEAD_GENESIS)
        );
        (, bytes memory tamperedData) = LibMigrationRegistry.applyMigrationHistoryV3Call(
            safe,
            LibRbacMigration.STOX_RBAC_NAMESPACE,
            LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER,
            euAt - 1,
            LibMigrationRegistry.onto(safe, LibRbacMigration.STOX_RBAC_NAMESPACE, MIGRATION_HEAD_GENESIS)
        );
        string memory tampered = vm.replace(json, vm.toString(euData), vm.toString(tamperedData));
        assertTrue(keccak256(bytes(tampered)) != keccak256(bytes(json)), "tamper did not apply");
        string memory tamperedPath =
            string.concat("out/20261022-backfill-migration-registry-v3-tampered-", vm.toString(block.chainid), ".json");
        vm.writeFile(tamperedPath, tampered);
        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.ArtifactMismatch.selector, "data"));
        script.verify(tamperedPath);
    }

    function testPreflightRefusesSafeOffPolicy() external {
        (BackfillMigrationRegistryV3Harness script, address safe) = setUpBase();
        if (spent()) return;
        vm.mockCall(safe, abi.encodeWithSignature("getThreshold()"), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector, safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD, 1
            )
        );
        script.callPreflight();
    }

    function testPreflightRefusesTimelockOffState() external {
        (BackfillMigrationRegistryV3Harness script,) = setUpBase();
        if (spent()) return;
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.mockCall(timelock, abi.encodeCall(ITimelockControllerState.getMinDelay, ()), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMinDelayMismatch.selector,
                timelock,
                LibTimelockInvariants.TIMELOCK_MIN_DELAY,
                1
            )
        );
        script.callPreflight();
    }

    function testPostStateRefusesUncarriedRecord() external {
        (BackfillMigrationRegistryV3Harness script, address safe) = setUpBase();
        if (spent()) return;
        vm.expectRevert(
            abi.encodeWithSelector(
                BackfillRecordMismatch.selector,
                LibStoxMigrations.GOVERNANCE_TIMELOCK,
                V2.applied(safe, LibStoxMigrations.NAMESPACE, LibStoxMigrations.GOVERNANCE_TIMELOCK),
                0
            )
        );
        script.callAssertPostState();
    }

    function executeBackfill(BackfillMigrationRegistryV3Harness script, address safe) internal {
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), script.callAuthorBundle());
        script.callAssertPostState();
    }

    function testPostStateRefusesDeployLineMovedOn() external {
        (BackfillMigrationRegistryV3Harness script, address safe) = setUpBase();
        if (spent()) return;
        executeBackfill(script, safe);
        bytes32 other = keccak256("some other migration");
        vm.prank(safe);
        LibMigrationRegistry.applyMigrationV3(
            safe,
            LibStoxMigrations.NAMESPACE,
            other,
            LibStoxMigrations.onto(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY)
        );
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRegistryV3Line.selector, LibStoxMigrations.NAMESPACE, other));
        script.callAssertPostState();
    }

    function testPostStateRefusesRbacLineMovedOn() external {
        (BackfillMigrationRegistryV3Harness script, address safe) = setUpBase();
        if (spent()) return;
        executeBackfill(script, safe);
        bytes32 other = keccak256("some other migration");
        vm.prank(safe);
        LibMigrationRegistry.applyMigrationV3(
            safe,
            LibRbacMigration.STOX_RBAC_NAMESPACE,
            other,
            LibMigrationRegistry.onto(
                safe, LibRbacMigration.STOX_RBAC_NAMESPACE, LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(UnexpectedRegistryV3Line.selector, LibRbacMigration.STOX_RBAC_NAMESPACE, other)
        );
        script.callAssertPostState();
    }

    function testPostStateRefusesOrchestratorMissingEmergency() external {
        (BackfillMigrationRegistryV3Harness script, address safe) = setUpBase();
        if (spent()) return;
        executeBackfill(script, safe);
        address instance = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        vm.mockCall(instance, abi.encodeCall(IAccessControl.hasRole, (keccak256("EMERGENCY"), safe)), abi.encode(false));
        vm.expectRevert(
            abi.encodeWithSelector(OrchestratorRoleMissing.selector, instance, keccak256("EMERGENCY"), safe)
        );
        script.callAssertPostState();
    }

    function testPostStateRefusesSafeOffPolicy() external {
        (BackfillMigrationRegistryV3Harness script, address safe) = setUpBase();
        if (spent()) return;
        executeBackfill(script, safe);
        vm.mockCall(safe, abi.encodeWithSignature("getThreshold()"), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector, safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD, 1
            )
        );
        script.callAssertPostState();
    }
}
