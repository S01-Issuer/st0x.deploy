// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {LibRainDeploy} from "rain-deploy-0.1.11/src/lib/LibRainDeploy.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";
import {LibMigrationInvariant} from "../../../../src/lib/LibMigrationInvariant.sol";
import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";

/// @title BeaconOwnerMigrationPinTest
/// @notice Reads each of the three V1 beacons' `owner()` from Base head and
/// asserts, via `LibMigrationInvariant`, that it is either the deploy EOA
/// (`LibProdDeployV1.BEACON_INITIAL_OWNER`) or the Safe
/// (`LibSafeInvariants.STOX_TOKEN_OWNER_SAFE`) until
/// `BEACON_OWNER_MIGRATION_DEADLINE`; from that timestamp on only the Safe
/// is accepted and an EOA-owned beacon trips `MigrationDeadlinePassed`.
///
/// @dev Unpinned Base head fork so `block.timestamp` is real. Pinning a
/// block would freeze the deadline check to whichever timestamp that block
/// carried, which is the one thing a deadline-gated invariant must not do.
///
/// When the migration lands on chain the owner reads flip from EOA to Safe
/// and this test moves from the "pre acceptable" branch to the "post
/// required" branch with no code change. If it has not landed by the
/// deadline the test red-lines and forces an operator choice: run the
/// script, move the deadline, or delete the invariant.
contract BeaconOwnerMigrationPinTest is Test {
    /// @notice Unix timestamp (`2026-09-01T00:00:00Z`) past which only the
    /// Safe-owned post-state is accepted: the operator-SLA cut-off for the
    /// beacon-owner migration. Moving it earlier tightens the forcing
    /// function and later loosens it; both are sanctioned, and neither is
    /// the same as deleting the check.
    uint256 internal constant BEACON_OWNER_MIGRATION_DEADLINE = 1_788_220_800;

    /// @notice Assert the migration-window invariant on a single beacon.
    function assertBeaconOwnerMigrationInvariant(address beacon, string memory label) internal view {
        LibMigrationInvariant.assertMigration(
            label,
            Ownable(beacon).owner(),
            LibProdDeployV1.BEACON_INITIAL_OWNER,
            LibBeaconInvariants.PROD_BEACON_OWNER,
            BEACON_OWNER_MIGRATION_DEADLINE
        );
    }

    /// @notice Each of the three V1 beacons is either EOA-owned or
    /// Safe-owned; any third owner fails. Against Base head, so drift into a
    /// third owner surfaces immediately and the deadline transition surfaces
    /// on cron without anyone editing this file.
    function testV1BeaconOwnersInMigrationWindow() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertBeaconOwnerMigrationInvariant(LibProdDeployV1.STOX_RECEIPT_BEACON_V1, "STOX_RECEIPT_BEACON_V1.owner()");
        assertBeaconOwnerMigrationInvariant(
            LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1, "STOX_RECEIPT_VAULT_BEACON_V1.owner()"
        );
        assertBeaconOwnerMigrationInvariant(
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1, "STOX_WRAPPED_TOKEN_VAULT_BEACON_V1.owner()"
        );
    }
}
