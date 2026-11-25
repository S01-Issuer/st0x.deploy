// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibServiceSignerRevoke, ServiceSignerStillHoldsRole} from "../../src/lib/LibServiceSignerRevoke.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {ZerogRootLineScriptTest} from "./ZerogRootLineScriptTest.sol";

/// @dev The service signer's state on 0G's US authoriser, and the ways to move it off the state the revoke produces.
abstract contract ZerogServiceSignerState is ZerogRootLineScriptTest {
    function usAuthoriser() internal pure returns (address) {
        return LibAuthoriserInvariants.authoriserForChainId(LibSafeInvariants.ZEROG_CHAIN_ID);
    }

    function signer() internal pure returns (address) {
        return LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
    }

    function revokeId() internal pure returns (bytes32) {
        return LibServiceSignerRevoke.operationId(zerogTimelock(), LibSafeInvariants.ZEROG_CHAIN_ID);
    }

    /// As the timelock, which administers both roles.
    function grantSigner(bool deposit) internal returns (bytes32 role) {
        role = deposit ? keccak256("DEPOSIT") : keccak256("WITHDRAW");
        vm.prank(zerogTimelock());
        IAccessControl(usAuthoriser()).grantRole(role, signer());
    }

    /// As the Safe, the timelock's proposer.
    function scheduleRevoke() internal {
        vm.prank(address(zerogSafe()));
        (bool ok,) = zerogTimelock().call(LibServiceSignerRevoke.scheduleCalldata(LibSafeInvariants.ZEROG_CHAIN_ID));
        assertTrue(ok, "the Safe schedules the revoke");
    }

    /// As a stranger, 48h after the Safe schedules it.
    function executeRevoke() internal {
        scheduleRevoke();
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibServiceSignerRevoke.batch(LibSafeInvariants.ZEROG_CHAIN_ID);
        vm.prank(address(0xdead));
        TimelockController(payable(zerogTimelock()))
            .executeBatch(targets, values, payloads, bytes32(0), LibServiceSignerRevoke.SALT);
        assertTrue(TimelockController(payable(zerogTimelock())).isOperationDone(revokeId()), "revoke executed");
    }

    /// An executed revoke batch changed nothing on 0G and cannot be cancelled, so it does not block the record.
    function testZerogAnExecutedRevokeDoesNotBlock() external {
        executeRevoke();
        sScript.callPreflight();
        executeBundle();
        sScript.callAssertPostState();
    }

    function testZerogSignerHoldsCertifyOnly() external view {
        LibServiceSignerRevoke.assertRevoked(usAuthoriser());
        assertTrue(IAccessControl(usAuthoriser()).hasRole(keccak256("CERTIFY"), signer()), "CERTIFY");
    }

    function testZerogPreflightRefusesASignerWithEitherRole(bool deposit) external {
        bytes32 role = grantSigner(deposit);
        vm.expectRevert(abi.encodeWithSelector(ServiceSignerStillHoldsRole.selector, role));
        sScript.callPreflight();
    }

    function testZerogLandsWithNothingScheduled() external {
        executeBundle();
        assertFalse(TimelockController(payable(zerogTimelock())).isOperation(revokeId()), "nothing scheduled");
        LibServiceSignerRevoke.assertRevoked(usAuthoriser());
        sScript.callAssertPostState();
    }
}
