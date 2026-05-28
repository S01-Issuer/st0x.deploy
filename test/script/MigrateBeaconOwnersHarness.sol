// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibSafeOps} from "../../src/lib/LibSafeOps.sol";

/// @title MigrateBeaconOwnersHarness
/// @notice External-call shim around the migration steps so `vm.expectRevert`
/// can intercept the typed errors raised by `LibSafeInvariants`. Library
/// `internal` functions inline into the test and would fail the
/// `expectRevert` depth check otherwise. The harness mirrors the exact
/// sequence `MigrateBeaconOwners.run()` performs, minus the `vm.broadcast`
/// wrapper (the test drives the ownership transfer via `vm.prank(EOA)` to
/// simulate the on-chain broadcast's effect).
contract MigrateBeaconOwnersHarness {
    function callAssertBeaconInvariants(address beacon, address expectedOwner, address expectedImpl) external view {
        LibSafeInvariants.assertBeaconInvariants(beacon, expectedOwner, expectedImpl);
    }

    function callSimulateBeaconNPlus1(IGnosisSafe safe, address beacon, address currentImpl, uint256 threshold)
        external
    {
        LibSafeOps.simulateBeaconNPlus1(safe, beacon, currentImpl, threshold);
    }
}
