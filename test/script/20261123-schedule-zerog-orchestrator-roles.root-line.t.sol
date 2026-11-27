// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {LibSafe} from "rain-deploy-0.1.43/src/lib/LibSafe.sol";

import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {ScheduleZerogOrchestratorRolesHarness} from "./ScheduleZerogOrchestratorRolesHarness.sol";
import {ZerogOrchestratorRolesFixture} from "./ZerogOrchestratorRolesFixture.sol";

/// @title ScheduleZerogOrchestratorRolesRootLineTest
/// @notice The schedule on live 0G, onto the token creation's record as Safe nonce 5 wrote it.
contract ScheduleZerogOrchestratorRolesRootLineTest is ZerogOrchestratorRolesFixture, RootLineRecordScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new ScheduleZerogOrchestratorRolesHarness("root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.CREATE_ZEROG_TOKENS;
    }

    function landBeforeOnto() internal override {
        forkZerogBeforeTheTokenRecord();
    }

    function landOnto() internal override {
        landZerogTokenRecord();
    }

    /// @dev Past the delay the post-state refuses the ready operation before the record.
    function latestRecordAge() internal pure override returns (uint256) {
        return LibTimelockInvariants.TIMELOCK_MIN_DELAY - 1;
    }

    function testPreflightRefusesASafeOffPolicy() external {
        vm.mockCall(safeAddress(), abi.encodeCall(OwnerManager.getThreshold, ()), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector,
                safeAddress(),
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
                1
            )
        );
        sScript.callPreflight();
    }
}
