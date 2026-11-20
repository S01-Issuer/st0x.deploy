// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";

import {bindBeaconInitialOwnerDeclaration} from "../../script/20261022-bind-beacon-initial-owner.s.sol";
import {orchestratorAdminToTimelockDeclaration} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {
    handSafeOwnedBaseVaultsToTimelockDeclaration
} from "../../script/20261103-hand-safe-owned-base-vaults-to-timelock.s.sol";
import {
    ExecuteUnderlyingNaming,
    executeUnderlyingNamingDeclaration
} from "../../script/20261021-execute-underlying-naming.s.sol";
import {
    scheduleUnderlyingNamingBeaconsDeclaration
} from "../../script/20261021-schedule-underlying-naming-beacons.s.sol";
import {scheduleUnderlyingNamingRenameDeclaration} from "../../script/20261021-schedule-underlying-naming-rename.s.sol";
import {
    scheduleRevokeServiceSignerDeclaration
} from "../../script/20261109-schedule-revoke-service-signer-deposit-withdraw.s.sol";
import {
    executeRevokeServiceSignerDeclaration
} from "../../script/20261109-execute-revoke-service-signer-deposit-withdraw.s.sol";
import {qsepSetFleetAuthoriserDeclaration} from "../../script/20261111-qsep-set-fleet-authoriser.s.sol";
import {bindOrchestratorConfigDeclaration} from "../../script/20261113-bind-orchestrator-config.s.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibServiceSignerRevoke} from "../../src/lib/LibServiceSignerRevoke.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxMigrations, ZerogArmPendingDecision} from "../../src/lib/LibStoxMigrations.sol";
import {LibTokenInvariants} from "../../src/lib/LibTokenInvariants.sol";
import {ExecuteUnderlyingNamingHarness} from "./ExecuteUnderlyingNamingHarness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {ScheduleUnderlyingNamingBeaconsHarness} from "./ScheduleUnderlyingNamingBeaconsHarness.sol";
import {ScheduleUnderlyingNamingRenameHarness} from "./ScheduleUnderlyingNamingRenameHarness.sol";
import {ZerogRootLineFixture} from "./ZerogRootLineFixture.sol";

/// @title ZerogRootLineTest
/// @notice 0G's root line past the token creation: the fixture's line is the declared one, the migrations whose 0G arm
/// waits on a decision refuse 0G loudly at their onto, and the whole line walks through every other 0G arm as the
/// record alone, changing nothing else.
contract ZerogRootLineTest is ZerogRootLineFixture {
    string internal constant EMERGENCY_DECISION = "whether the 0G Safe holds EMERGENCY_ROLE on the orchestrator";
    string internal constant NAMING_DECISION = "whether the underlying naming applies on 0G";

    function setUp() public {
        landZerogTokens();
    }

    function declarations() internal pure returns (ScriptDeclaration[10] memory) {
        return [
            bindBeaconInitialOwnerDeclaration(),
            orchestratorAdminToTimelockDeclaration(),
            handSafeOwnedBaseVaultsToTimelockDeclaration(),
            scheduleUnderlyingNamingBeaconsDeclaration(),
            scheduleUnderlyingNamingRenameDeclaration(),
            executeUnderlyingNamingDeclaration(),
            scheduleRevokeServiceSignerDeclaration(),
            executeRevokeServiceSignerDeclaration(),
            qsepSetFleetAuthoriserDeclaration(),
            bindOrchestratorConfigDeclaration()
        ];
    }

    /// `migrations.json` holds every script's declaration, so a migration declared later onto 0G's line, with no 0G
    /// landing here, shows up in it.
    function testZerogLineIsTheManifestsLineAfterTheTokenCreation() external view {
        string memory json = vm.readFile("migrations.json");
        string memory chain = string.concat(".chains.", vm.toString(LibSafeInvariants.ZEROG_CHAIN_ID), ".onto");
        uint256 rows = 0;
        while (vm.keyExistsJson(json, string.concat(".migrations[", vm.toString(rows), "]"))) rows++;
        bytes32[10] memory line = zerogLine();
        bytes32 onto = LibStoxMigrations.CREATE_ZEROG_TOKENS;
        for (uint256 i = 0; i <= line.length; i++) {
            bytes32 next = bytes32(0);
            for (uint256 r = 0; r < rows; r++) {
                string memory at = string.concat(".migrations[", vm.toString(r), "]");
                if (vm.parseJsonBytes32(json, string.concat(at, chain)) == onto) {
                    assertEq(next, bytes32(0), "one migration per onto");
                    next = vm.parseJsonBytes32(json, string.concat(at, ".id"));
                }
            }
            if (i == line.length) {
                assertEq(next, bytes32(0), "nothing after the line's end");
            } else {
                assertEq(next, line[i], "line order");
                onto = next;
            }
        }
    }

    function testZerogLineIsTheDeclaredLine() external pure {
        bytes32[10] memory line = zerogLine();
        ScriptDeclaration[10] memory declared = declarations();
        bytes32 onto = LibStoxMigrations.CREATE_ZEROG_TOKENS;
        for (uint256 i = 0; i < line.length; i++) {
            assertEq(declared[i].id, line[i], "id");
            assertEq(declared[i].onto, onto, "onto");
            assertFalse(declared[i].history, "history");
            onto = line[i];
        }
    }

    function expectPending(bytes32 migration, string memory decision) internal {
        vm.expectRevert(abi.encodeWithSelector(ZerogArmPendingDecision.selector, migration, decision));
    }

    function testOrchestratorAdminToTimelockWaitsOnTheEmergencyDecision() external {
        landZerogLineThrough(LibStoxMigrations.BIND_BEACON_INITIAL_OWNER);
        OrchestratorAdminToTimelockHarness script = new OrchestratorAdminToTimelockHarness("zerog-pending");
        expectPending(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK, EMERGENCY_DECISION);
        script.callPreflight();
        expectPending(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK, EMERGENCY_DECISION);
        script.run();
    }

    function testNamingBeaconsWaitOnTheNamingDecision() external {
        landZerogLineThrough(LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK);
        // The harness takes the release as frozen, so only the 0G refusal stands in the way.
        ScheduleUnderlyingNamingBeaconsHarness script = new ScheduleUnderlyingNamingBeaconsHarness("zerog-pending");
        expectPending(LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS, NAMING_DECISION);
        script.callPreflight();
    }

    function testNamingRenameWaitsOnTheNamingDecision() external {
        landZerogLineThrough(LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS);
        ScheduleUnderlyingNamingRenameHarness script = new ScheduleUnderlyingNamingRenameHarness("zerog-pending");
        expectPending(LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME, NAMING_DECISION);
        script.callPreflight();
    }

    function testNamingExecutionWaitsOnTheNamingDecision() external {
        landZerogLineThrough(LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME);
        ExecuteUnderlyingNamingHarness script = new ExecuteUnderlyingNamingHarness("zerog-pending");
        expectPending(LibStoxMigrations.EXECUTE_UNDERLYING_NAMING, NAMING_DECISION);
        script.callPreflight();
        ExecuteUnderlyingNaming execution = new ExecuteUnderlyingNaming();
        expectPending(LibStoxMigrations.EXECUTE_UNDERLYING_NAMING, NAMING_DECISION);
        execution.execute();
    }

    /// Every 0G arm lands as the record alone, one Safe transaction each, and the state #620 left stays as it was:
    /// the authoriser grants, the beacons, the vault owners, the unbound config names, and the 0.1.30 orchestrator.
    function testZerogLineWalksPastTheTokenCreation() external {
        Safe safe = Safe(payable(zerogSafe()));
        uint256 nonce = safe.nonce();
        landZerogLineThrough(LibStoxMigrations.BIND_ORCHESTRATOR_CONFIG);

        bytes32[10] memory line = zerogLine();
        uint256 bundles = 0;
        for (uint256 i = 0; i < line.length; i++) {
            assertEq(LibStoxMigrations.applied(line[i]), block.timestamp, "recorded");
            if (!zerogPendingDecision(line[i])) bundles++;
        }
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.BIND_ORCHESTRATOR_CONFIG, "line at its end");
        // The stand-in records are pranked writes, not Safe transactions.
        assertEq(safe.nonce(), nonce + bundles, "one Safe transaction per 0G arm");

        address us = LibAuthoriserInvariants.authoriserForChainId(block.chainid);
        LibAuthoriserInvariants.assertHeld(
            us, LibAuthoriserInvariants.expectedGrantsOn(block.chainid, zerogSafe(), zerogTimelock())
        );
        LibServiceSignerRevoke.assertRevoked(us);
        LibAuthoriserInvariants.assertExpectedEuGrants(
            LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid),
            zerogTimelock(),
            LibAuthoriserInvariants.GRANTEE_EU_MINTER
        );
        LibBeaconInvariants.assertProdBeaconsOwnedBy(block.chainid, zerogTimelock());
        LibTokenInvariants.assertUniformOwnership(zerogTokens(), zerogTimelock());
        assertFalse(rootBound(LibStoxConfig.BEACON_INITIAL_OWNER_NAME), "beacon initial owner unbound");
        assertFalse(rootBound(LibStoxConfig.ORCHESTRATOR_BEACON_NAME), "orchestrator beacon unbound");
        assertFalse(rootBound(LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME), "orchestrator initial admin unbound");
        assertZerogOrchestratorAsLive();
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe);
    }
}
