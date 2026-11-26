// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";

import {bindBeaconInitialOwnerDeclaration} from "../../script/20261022-bind-beacon-initial-owner.s.sol";
import {orchestratorAdminToTimelockDeclaration} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {
    handSafeOwnedBaseVaultsToTimelockDeclaration
} from "../../script/20261103-hand-safe-owned-base-vaults-to-timelock.s.sol";
import {executeUnderlyingNamingDeclaration} from "../../script/20261021-execute-underlying-naming.s.sol";
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
import {scheduleZerogOrchestratorRolesDeclaration} from "../../script/20261123-schedule-zerog-orchestrator-roles.s.sol";
import {executeZerogOrchestratorRolesDeclaration} from "../../script/20261123-execute-zerog-orchestrator-roles.s.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibServiceSignerRevoke} from "../../src/lib/LibServiceSignerRevoke.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants} from "../../src/lib/LibTokenInvariants.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";
import {LibZerogOrchestratorRoles} from "../../src/lib/LibZerogOrchestratorRoles.sol";
import {ScheduleUnderlyingNamingRenameHarness} from "./ScheduleUnderlyingNamingRenameHarness.sol";
import {ZerogRootLineFixture} from "./ZerogRootLineFixture.sol";

/// @title ZerogRootLineTest
/// @notice 0G's root line past the token creation: the fixture's line is the declared one, and the whole line walks
/// through the orchestrator roles, the underlying naming and every other 0G arm as the record alone, changing nothing
/// the roles batch and the naming do not.
contract ZerogRootLineTest is ZerogRootLineFixture {
    function setUp() public {
        forkZerogAtTheTokenRecord();
    }

    function declarations() internal pure returns (ScriptDeclaration[12] memory) {
        return [
            scheduleZerogOrchestratorRolesDeclaration(),
            executeZerogOrchestratorRolesDeclaration(),
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
        bytes32[12] memory line = zerogLine();
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
        bytes32[12] memory line = zerogLine();
        ScriptDeclaration[12] memory declared = declarations();
        bytes32 onto = LibStoxMigrations.CREATE_ZEROG_TOKENS;
        for (uint256 i = 0; i < line.length; i++) {
            assertEq(declared[i].id, line[i], "id");
            assertEq(declared[i].onto, onto, "onto");
            assertFalse(declared[i].history, "history");
            onto = line[i];
        }
    }

    /// The orchestrator roles land as the signers and a stranger land them, the underlying naming as the Safe and a
    /// roleless key land it, every other later 0G arm as the record alone, one Safe transaction each, and nothing else
    /// changes: the authoriser grants and the orchestrator roles as the batch leaves them, the beacons on the naming's
    /// implementations, every 0G vault renamed, the vault owners and the unbound config names.
    function testZerogLineWalksPastTheTokenCreation() external {
        Safe safe = zerogSafe();
        uint256 nonce = safe.nonce();
        landZerogLineThrough(LibStoxMigrations.BIND_ORCHESTRATOR_CONFIG);

        bytes32[12] memory line = zerogLine();
        uint256 recordedAt = block.timestamp;
        for (uint256 i = line.length; i > 0; i--) {
            assertEq(LibStoxMigrations.applied(line[i - 1]), recordedAt, "recorded");
            // An execution is recorded after the delay its schedule waited out.
            if (
                line[i - 1] == LibStoxMigrations.EXECUTE_ZEROG_ORCHESTRATOR_ROLES
                    || line[i - 1] == LibStoxMigrations.EXECUTE_UNDERLYING_NAMING
            ) recordedAt -= LibTimelockInvariants.TIMELOCK_MIN_DELAY;
        }
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.BIND_ORCHESTRATOR_CONFIG, "line at its end");
        assertEq(safe.nonce(), nonce + line.length, "one Safe transaction per 0G arm");

        assertEq(
            IBeacon(LibUnderlyingNamingRollout.receiptVaultBeacon(block.chainid)).implementation(),
            LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION,
            "vault beacon on the naming's implementation"
        );
        assertEq(
            IBeacon(LibUnderlyingNamingRollout.wrappedTokenVaultBeacon(block.chainid)).implementation(),
            LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_IMPLEMENTATION,
            "wrapper beacon on the naming's implementation"
        );
        new ScheduleUnderlyingNamingRenameHarness("zerog-walk").callAssertRenamed(block.chainid);

        address us = LibAuthoriserInvariants.authoriserForChainId(block.chainid);
        LibAuthoriserInvariants.assertExpectedGrants(us, address(safe), zerogTimelock());
        LibServiceSignerRevoke.assertRevoked(us);
        LibAuthoriserInvariants.assertExpectedEuGrants(
            LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid),
            zerogTimelock(),
            LibAuthoriserInvariants.GRANTEE_EU_MINTER
        );
        LibBeaconInvariants.assertProdBeaconsOwnedBy(block.chainid, zerogTimelock());
        LibTokenInvariants.assertUniformOwnership(LibTokenInvariants.productionTokensZerog(), zerogTimelock());
        assertFalse(rootBound(LibStoxConfig.BEACON_INITIAL_OWNER_NAME), "beacon initial owner unbound");
        assertFalse(rootBound(LibStoxConfig.ORCHESTRATOR_BEACON_NAME), "orchestrator beacon unbound");
        assertFalse(rootBound(LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME), "orchestrator initial admin unbound");
        LibOrchestratorInvariants.assertBeaconSet();
        LibOrchestratorInvariants.assertInstance();
        LibOrchestratorInvariants.assertExpectedGrants(address(safe), zerogTimelock());
        LibZerogOrchestratorRoles.assertGranted();
        assertFalse(
            IAccessControl(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE).hasRole(bytes32(0), address(safe)),
            "the Safe is not the orchestrator's admin"
        );
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe);
    }
}
