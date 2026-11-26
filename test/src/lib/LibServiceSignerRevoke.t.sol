// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibServiceSignerRevoke, RevokeBatchPending} from "../../../src/lib/LibServiceSignerRevoke.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";

/// @title LibServiceSignerRevokeTest
/// @notice `assertNotPending` refuses exactly while the chain's revoke batch is waiting or ready on the timelock.
contract LibServiceSignerRevokeTest is Test {
    TimelockController internal sTimelock;

    function setUp() external {
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        sTimelock = new TimelockController(LibTimelockInvariants.TIMELOCK_MIN_DELAY, proposers, executors, address(0));
    }

    function externalAssertNotPending(uint256 chainId) external view {
        LibServiceSignerRevoke.assertNotPending(address(sTimelock), chainId);
    }

    function chainIdAt(uint8 index) internal pure returns (uint256) {
        uint256[6] memory chainIds = [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID,
            LibSafeInvariants.ZEROG_CHAIN_ID
        ];
        return chainIds[index % chainIds.length];
    }

    function schedule(uint256 chainId) internal {
        (bool ok,) = address(sTimelock).call(LibServiceSignerRevoke.scheduleCalldata(chainId));
        assertTrue(ok, "scheduled");
    }

    function expectPendingRefused(uint256 chainId) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                RevokeBatchPending.selector, LibServiceSignerRevoke.operationId(address(sTimelock), chainId)
            )
        );
    }

    function testFuzzAssertNotPendingPassesWithNothingScheduled(uint8 index) external view {
        this.externalAssertNotPending(chainIdAt(index));
    }

    function testFuzzAssertNotPendingRefusesAWaitingBatch(uint8 index) external {
        uint256 chainId = chainIdAt(index);
        schedule(chainId);
        expectPendingRefused(chainId);
        this.externalAssertNotPending(chainId);
    }

    function testFuzzAssertNotPendingRefusesAReadyBatch(uint8 index) external {
        uint256 chainId = chainIdAt(index);
        schedule(chainId);
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        assertTrue(sTimelock.isOperationReady(LibServiceSignerRevoke.operationId(address(sTimelock), chainId)));
        expectPendingRefused(chainId);
        this.externalAssertNotPending(chainId);
    }

    function testFuzzAssertNotPendingPassesAnExecutedBatch(uint8 index) external {
        uint256 chainId = chainIdAt(index);
        schedule(chainId);
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibServiceSignerRevoke.batch(chainId);
        sTimelock.executeBatch(targets, values, payloads, bytes32(0), LibServiceSignerRevoke.SALT);
        assertTrue(sTimelock.isOperationDone(LibServiceSignerRevoke.operationId(address(sTimelock), chainId)));
        this.externalAssertNotPending(chainId);
    }

    function testFuzzAssertNotPendingPassesACancelledBatch(uint8 index) external {
        uint256 chainId = chainIdAt(index);
        schedule(chainId);
        sTimelock.cancel(LibServiceSignerRevoke.operationId(address(sTimelock), chainId));
        this.externalAssertNotPending(chainId);
    }

    function testFuzzAssertNotPendingPassesTheBatchUnderAnotherSalt(uint8 index, bytes32 salt) external {
        vm.assume(salt != LibServiceSignerRevoke.SALT);
        uint256 chainId = chainIdAt(index);
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibServiceSignerRevoke.batch(chainId);
        sTimelock.scheduleBatch(targets, values, payloads, bytes32(0), salt, LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        this.externalAssertNotPending(chainId);
    }
}
