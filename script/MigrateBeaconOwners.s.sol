// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";

import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibProdDeployV1} from "../src/lib/LibProdDeployV1.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeOps} from "../src/lib/LibSafeOps.sol";

/// @title MigrateBeaconOwners
/// @notice Forge script that transfers ownership of the three production V1
/// beacons that live ST0x tokens actually use — the receipt beacon, the
/// receipt vault beacon, and the wrapped token vault beacon — from the
/// externally-owned account at `LibProdDeployV1.BEACON_INITIAL_OWNER`
/// (rainlang.eth) to the ST0x token-owner Safe at
/// `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE`.
///
/// Unlike the threshold migration, this is a direct EOA-broadcast operation,
/// not a Safe-routed transaction: ownership of an `Ownable` beacon transfers
/// by the current owner calling `transferOwnership`, and the current owner is
/// the EOA. The script therefore emits no Tx Builder JSON artifact — the
/// output is the on-chain `transferOwnership` transaction(s) themselves.
///
/// @dev The flow is the operational-script standard shape adapted for a
/// direct-broadcast op:
///
/// 1. **Pre-flight** — every beacon is asserted to be in the expected
///    EOA-owned state via `LibSafeInvariants.assertBeaconInvariants` (deployed
///    contract, pinned OZ `UpgradeableBeacon` codehash, EOA owner, pinned
///    current implementation). If any beacon has drifted, the script aborts
///    before broadcasting anything.
/// 2. **Broadcast** — `transferOwnership(STOX_TOKEN_OWNER_SAFE)` is called on
///    each beacon under `vm.startBroadcast()`. Three separate transactions
///    (one per beacon) rather than a batch: simpler, and abortable partway if
///    the first goes sideways.
/// 3. **Post-state** — every beacon is re-asserted, now expecting the Safe as
///    owner and the same (unchanged) implementation.
/// 4. **n+1 reversibility** — for each beacon, `simulateBeaconNPlus1` proves
///    the Safe can act on the beacon post-migration by running an idempotent
///    `upgradeTo(currentImpl)` through the Safe's `execTransaction` (exercising
///    the threshold gate both ways). The n+1 runs as a fork-local simulation;
///    it is not broadcast.
///
/// Execution mode:
/// ```shell
/// forge script script/MigrateBeaconOwners.s.sol \
///   --rpc-url base --broadcast --private-key <EOA key>
/// ```
contract MigrateBeaconOwners is Script {
    /// @notice The three V1 beacons whose ownership is migrated. Order is
    /// fixed: receipt beacon, receipt vault beacon, wrapped token vault
    /// beacon. The parallel `currentImpls()` helper returns each beacon's
    /// pinned current implementation in the same order.
    /// @return The three beacon addresses to migrate.
    function beacons() internal pure returns (address[3] memory) {
        return [
            LibProdDeployV1.STOX_RECEIPT_BEACON_V1,
            LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1,
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1
        ];
    }

    /// @notice The pinned current implementation for each beacon, in the same
    /// order as `beacons()`. Asserted unchanged across the ownership transfer
    /// (the migration changes the owner, never the implementation) and used as
    /// the idempotent `upgradeTo` argument in the n+1 check.
    /// @return The three implementation addresses, index-aligned with
    /// `beacons()`.
    function currentImpls() internal pure returns (address[3] memory) {
        return [
            LibProdDeployV1.STOX_RECEIPT_IMPLEMENTATION,
            LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION,
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION
        ];
    }

    /// @notice Run the beacon-ownership migration: pre-flight every beacon
    /// against the EOA-owned state, broadcast the three `transferOwnership`
    /// calls, re-assert every beacon against the Safe-owned state, then prove
    /// each beacon's n+1 reversibility through the Safe. Broadcasts the
    /// transfers; the n+1 checks are fork-local simulations only.
    function run() external {
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        address[3] memory beaconList = beacons();
        address[3] memory implList = currentImpls();

        // Pre-flight: every beacon is in the expected EOA-owned state. Reverts
        // with the relevant typed error from `LibSafeInvariants` on the first
        // drift, before any broadcast happens.
        for (uint256 i = 0; i < beaconList.length; i++) {
            LibSafeInvariants.assertBeaconInvariants(
                beaconList[i], LibProdDeployV1.BEACON_INITIAL_OWNER, implList[i]
            );
        }

        // Broadcast the ownership transfers from the EOA. Three separate
        // transactions — Foundry submits each `transferOwnership` as its own
        // tx from the single script run.
        vm.startBroadcast();
        for (uint256 i = 0; i < beaconList.length; i++) {
            Ownable(beaconList[i]).transferOwnership(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        }
        vm.stopBroadcast();

        // Post-state: every beacon is now Safe-owned, implementations
        // unchanged.
        for (uint256 i = 0; i < beaconList.length; i++) {
            LibSafeInvariants.assertBeaconInvariants(beaconList[i], LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, implList[i]);
        }

        // n+1 reversibility: prove the Safe can act on each beacon by running
        // an idempotent `upgradeTo(currentImpl)` through the Safe's
        // `execTransaction`. The threshold gate is exercised both ways
        // (undersigned reverts with GS020, full threshold succeeds). Reads the
        // live threshold from `LibSafeInvariants` so the check tracks whatever the
        // Safe's current threshold is.
        for (uint256 i = 0; i < beaconList.length; i++) {
            LibSafeOps.simulateBeaconNPlus1(
                safe, beaconList[i], implList[i], LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
            );
        }

        console2.log("Beacon ownership migration pre-flight + post-state + n+1 checks passed.");
        console2.log("Transferred ownership of 3 beacons to:", vm.toString(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE));
    }
}
