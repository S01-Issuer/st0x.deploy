// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {LibMigrationInvariant} from "../../../../src/lib/LibMigrationInvariant.sol";
import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";

/// @title BeaconOwnerMigrationPinTest
/// @notice Live-fork pin of the beacon-ownership migration executed by
/// `script/MigrateBeaconOwners.s.sol` (PR #196). Reads each of the three V1
/// beacons' `owner()` from live Base head and asserts, via
/// `LibMigrationInvariant`, that the value is either the pre-migration EOA
/// (`LibProdDeployV1.BEACON_INITIAL_OWNER`) or the post-migration Safe
/// (`LibSafeInvariants.STOX_TOKEN_OWNER_SAFE`) — up until
/// `BEACON_OWNER_MIGRATION_DEADLINE`. From that timestamp on only the Safe is
/// accepted; any beacon still EOA-owned at that point trips
/// `MigrationDeadlinePassed` and red-lines the cron.
///
/// @dev Uses an unpinned Base head fork so `block.timestamp` is real. Pinning
/// a block would freeze the deadline check to whichever timestamp the pinned
/// block carried, which is exactly the wrong behaviour for a deadline-gated
/// invariant.
///
/// When the migration lands on-chain the beacon owner reads flip from EOA
/// to Safe and this test transitions from the "pre acceptable" branch to the
/// "post required" branch without any code change. If the migration has not
/// landed by the deadline this test red-lines and forces an operator choice:
/// run the script, extend the deadline, or delete the invariant.
contract BeaconOwnerMigrationPinTest is Test {
    /// @notice Unix timestamp past which only the Safe-owned post-state is
    /// accepted — the operator-SLA cut-off for the beacon-owner migration.
    /// `2026-09-01T00:00:00Z`. Past this instant the invariant demands the
    /// migration has landed on-chain; a later PR can move it earlier to
    /// tighten the forcing function or later to loosen it if the SLA shifts.
    uint256 internal constant BEACON_OWNER_MIGRATION_DEADLINE = 1_788_220_800;

    /// @notice Assert the migration-window invariant on a single beacon.
    function assertBeaconOwnerMigrationInvariant(address beacon, string memory label) internal view {
        LibMigrationInvariant.assertMigration(
            label,
            Ownable(beacon).owner(),
            LibProdDeployV1.BEACON_INITIAL_OWNER,
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,
            BEACON_OWNER_MIGRATION_DEADLINE
        );
    }

    /// @notice Each of the three V1 beacons `MigrateBeaconOwners` targets
    /// is either still EOA-owned or already Safe-owned. Runs against Base
    /// head so any drift into a third owner surfaces immediately, and the
    /// deadline transition surfaces automatically on cron.
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
