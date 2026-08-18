// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeOps} from "../src/lib/LibSafeOps.sol";

/// @title MigrateOrchestratorBeaconOwner
/// @notice **PENDING.** Transfers ownership of the ST0x orchestrator beacon
/// (`LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON`) on whichever chain
/// this is broadcast against, from the deploy EOA
/// (`LibProdDeployV4.BEACON_INITIAL_OWNER`, rainlang.eth) to that chain's
/// token-owner Safe — the orchestrator-beacon analogue of
/// `MigrateBeaconOwners` (Base token beacons, #253) and
/// `20260716`/`20260722-migrate-beacon-owners-*` (Ethereum / HyperEVM). The
/// beacon-set deployer's constructor bakes `BEACON_INITIAL_OWNER` as the
/// beacon's initial owner, so every chain the 0.1.8 closure ships to starts
/// EOA-owned and needs this migration.
///
/// @dev This is an **EOA broadcast, not a Safe artifact and not a CI
/// deploy-key dispatch**: an `Ownable` beacon transfers by its current owner
/// calling `transferOwnership`, and the current owner is the EOA — which is
/// why this script is deliberately absent from the `manual-broadcast.yaml`
/// registry (that dispatcher broadcasts as the CI deploy key). Broadcast as
/// the EOA, once per chain:
///
///   forge script script/20260818-migrate-orchestrator-beacon-owner.s.sol \
///     --rpc-url <base|ethereum|hyperevm> --broadcast --private-key <EOA key>
///
/// (HyperEVM additionally needs `--legacy`.)
///
/// Ordering: run any time after the chain carries the 0.1.8 closure
/// (`manual-sol-artifacts-0-1-8.yaml`) — the beacon exists from the
/// beacon-set deployer's constructor. Independent of the instance deploy
/// (`20260818-deploy-orchestrator`): beacon ownership gates `upgradeTo`,
/// not `deploy()`. The live-fork invariant
/// (`LibOrchestratorInvariants.assertBeaconSet`) accepts either owner until
/// `ST0X_ORCHESTRATOR_BEACON_OWNER_MIGRATION_DEADLINE` and only the Safe
/// after it, so cron red-lines any chain this migration misses.
///
/// The flow is the beacon-owner-migration standard shape:
///
/// 1. **Pre-flight** — the beacon is asserted in the EOA-owned state via
///    `LibBeaconInvariants.assertBeaconInvariants` (deployed, pinned OZ
///    `UpgradeableBeacon` codehash, EOA owner, pointing at the audited 0.1.8
///    orchestrator implementation). A drifted or already-migrated beacon
///    aborts before any broadcast — re-running after execution reverts on
///    the owner check rather than doing anything.
/// 2. **Broadcast** — one `transferOwnership(safe)` from the EOA.
/// 3. **Post-state** — the beacon is re-asserted, now Safe-owned, with the
///    implementation unchanged.
/// 4. **n+1 reversibility** — `LibSafeOps.simulateBeaconNPlus1` proves the
///    Safe can act on the beacon post-migration by routing an idempotent
///    `upgradeTo(currentImpl)` through the Safe's threshold-gated
///    `execTransaction`. Fork-local simulation, not broadcast.
contract MigrateOrchestratorBeaconOwner is Script {
    /// @notice Pre-flight the EOA-owned beacon, broadcast the ownership
    /// transfer to the active chain's token-owner Safe, re-assert the
    /// Safe-owned state, and prove the Safe can operate the beacon.
    function run() external {
        address beacon = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON;
        address impl = LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_8;
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);

        // Pre-flight: deployed, OZ beacon bytecode, still EOA-owned, pointing
        // at the audited 0.1.8 orchestrator impl. Reverts with the relevant
        // typed error on the first drift, before any broadcast happens.
        LibBeaconInvariants.assertBeaconInvariants(beacon, LibProdDeployV4.BEACON_INITIAL_OWNER, impl);

        console2.log("Migrating orchestrator beacon owner on chain id", block.chainid);
        console2.log("beacon:", beacon);
        console2.log("from (deploy EOA):", LibProdDeployV4.BEACON_INITIAL_OWNER);
        console2.log("to (token-owner Safe):", safe);

        vm.startBroadcast();
        Ownable(beacon).transferOwnership(safe);
        vm.stopBroadcast();

        // Post-state: Safe-owned, implementation unchanged.
        LibBeaconInvariants.assertBeaconInvariants(beacon, safe, impl);

        // n+1: the Safe can drive the beacon through its threshold-gated
        // exec — an idempotent upgradeTo(currentImpl), simulated on the fork.
        LibSafeOps.simulateBeaconNPlus1(
            IGnosisSafe(safe), beacon, impl, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
        );

        console2.log("Orchestrator beacon ownership transferred to the Safe; n+1 upgrade path proven.");
    }
}
