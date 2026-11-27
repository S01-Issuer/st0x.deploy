// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.38/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.38/src/lib/LibSafe.sol";
import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";

import {
    ExecuteUnderlyingNamingBeacons,
    ExecuteUnderlyingNamingBeaconsRecorded,
    UnderlyingNamingBeaconsNotExecuted
} from "../../script/20261021-execute-underlying-naming-beacons.s.sol";
import {ExecuteUnderlyingNamingBeaconsHarness} from "./ExecuteUnderlyingNamingBeaconsHarness.sol";
import {UnderlyingNamingRolloutFixture} from "./UnderlyingNamingRolloutFixture.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @title ExecuteUnderlyingNamingBeaconsRootLineTest
/// @notice The beacon execution record on Base, onto the beacon batch's
/// record, from the beacon batch scheduled and past its delay.
contract ExecuteUnderlyingNamingBeaconsRootLineTest is UnderlyingNamingRolloutFixture, RootLineRecordScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new ExecuteUnderlyingNamingBeaconsHarness("root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.EXECUTE_BEACON_UPGRADE;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.SCHEDULE_BEACON_UPGRADE;
    }

    function landBeforeOnto() internal override {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToBeaconSchedule();
        landBeaconSchedule();
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
    }

    /// @dev The beacon batch, whose last call writes the onto.
    function landOnto() internal override {
        new ExecuteUnderlyingNamingBeacons().execute();
    }

    function beaconOperationId() internal view returns (bytes32) {
        return LibUnderlyingNamingRollout.beaconOperationId(
            LibTimelockInvariants.timelockForChainId(block.chainid), block.chainid
        );
    }

    function beforeOntoPreflightRefusal(bytes32) internal view override returns (bytes memory) {
        return abi.encodeWithSelector(UnderlyingNamingBeaconsNotExecuted.selector, beaconOperationId());
    }

    function ownRecordPreflightRefusal() internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(ExecuteUnderlyingNamingBeaconsRecorded.selector, declaredId());
    }

    function testBundleIsTheRecordOntoTheBeaconRecord() external view {
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, 1, "record only");
        assertEq(txs[0].to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, "record target");
        assertEq(txs[0].value, 0, "record value");
        assertEq(
            txs[0].data,
            LibTestRootLine.recordCalldata(
                LibStoxMigrations.EXECUTE_BEACON_UPGRADE,
                LibStoxMigrations.SCHEDULE_BEACON_UPGRADE
            ),
            "record calldata"
        );
        assertEq(uint8(txs[0].operation), uint8(Enum.Operation.Call), "record operation");
    }

    /// @notice The line at the beacon record does not stand in for the
    /// executed beacon batch.
    function testPreflightRefusesTheBeaconRecordWithoutTheBeaconBatch() external {
        assertTrue(vm.revertToState(sBeforeOnto), "snapshot before the onto");
        LibTestRootLine.write(
            vm,
            safeAddress(),
            LibStoxMigrations.SCHEDULE_BEACON_UPGRADE,
            LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK
        );
        assertEq(LibStoxMigrations.head(), declaredOnto(), "line at the onto");
        vm.expectRevert(abi.encodeWithSelector(UnderlyingNamingBeaconsNotExecuted.selector, beaconOperationId()));
        sScript.callPreflight();
    }

    function testPreflightRefusesOnceRecorded() external {
        executeBundle();
        vm.expectRevert(
            abi.encodeWithSelector(
                ExecuteUnderlyingNamingBeaconsRecorded.selector, LibStoxMigrations.EXECUTE_BEACON_UPGRADE
            )
        );
        sScript.callPreflight();
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
