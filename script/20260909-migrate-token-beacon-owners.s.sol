// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibProdBeacons0_1_1} from "../src/lib/LibProdBeacons0_1_1.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {LibSafeOps} from "../src/lib/LibSafeOps.sol";

/// @notice The active chain's in-use production beacons are not the
/// deterministic 0.1.1 set, so this migration does not apply to it (Base
/// runs its V1-generation beacons, migrated by `MigrateBeaconOwners`).
/// @param chainId The active chain id.
error NotA0_1_1BootstrapChain(uint256 chainId);

/// @title MigrateTokenBeaconOwners
/// @notice Transfers ownership of the three ST0x production token beacons
/// (receipt, receipt vault, wrapped token vault) on whichever 0.1.1-bootstrap
/// chain this is broadcast against, from the deploy EOA
/// (`LibProdDeployV4.BEACON_INITIAL_OWNER`, rainlang.eth) to that chain's
/// token-owner Safe. The chain-generic successor of
/// `20260716-migrate-beacon-owners-ethereum` and
/// `20260722-migrate-beacon-owners-hyperevm`, which each hardcoded one chain:
/// every chain that bootstraps at 0.1.1 gets the SAME deterministic beacon
/// set (`LibProdBeacons0_1_1`), and the beacon-set deployer constructors bake
/// `BEACON_INITIAL_OWNER` as the initial owner, so the operation is identical
/// per chain and only the Safe differs. The Safe is resolved from
/// `block.chainid`, so a new chain is covered by its Safe pin alone.
///
/// The orchestrator beacon is deliberately NOT in scope: it arrives with the
/// 0.1.30 closure, not the 0.1.1 suites, and has its own migration
/// (`20260818-migrate-orchestrator-beacon-owner`).
///
/// @dev This is an **EOA broadcast, not a Safe artifact and not a CI
/// deploy-key dispatch**: an `Ownable` beacon transfers by its current owner
/// calling `transferOwnership`, and the current owner is the EOA — which is
/// why this script is absent from the `manual-broadcast.yaml` registry (that
/// dispatcher broadcasts as the CI deploy key). Broadcast as the EOA, once per
/// chain:
///
///   forge script script/20260909-migrate-token-beacon-owners.s.sol \
///     --rpc-url <network> --broadcast --private-key <EOA key>
///
/// (HyperEVM additionally needs `--legacy`.)
///
/// Ordering: run AFTER the 0.1.1 impl suites are deployed on the chain (the
/// beacons do not exist before) and BEFORE the token deploy — the
/// `20260807-deploy-missing-tokens` pre-flight hard-gates on
/// `assertProdBeaconsOwnedByChainSafe`. The beacons back no vaults yet at
/// that point, so this is pure ownership hand-off with no live-vault risk.
///
/// The flow is the beacon-owner-migration standard shape:
///
/// 1. **Pre-flight** — the active chain's in-use beacons must BE the 0.1.1
///    set (a chain on other beacons is refused), and each of the three is
///    asserted in the EOA-owned state via
///    `LibBeaconInvariants.assertBeaconInvariants` (deployed, pinned OZ
///    `UpgradeableBeacon` codehash, EOA owner, pointing at its audited 0.1.1
///    implementation). A drifted or already-migrated beacon aborts before
///    any broadcast — re-running after execution reverts on the owner check
///    rather than doing anything.
/// 2. **Broadcast** — three `transferOwnership(safe)` calls from the EOA.
/// 3. **Post-state** — every beacon is re-asserted, now Safe-owned, with its
///    implementation unchanged.
/// 4. **n+1 reversibility** — `LibSafeOps.simulateBeaconNPlus1` proves the
///    Safe can act on each beacon post-migration by routing an idempotent
///    `upgradeTo(currentImpl)` through the Safe's threshold-gated
///    `execTransaction`. Fork-local simulation, not broadcast.
contract MigrateTokenBeaconOwners is Script {
    /// @notice Number of token beacons migrated: receipt, receipt vault,
    /// wrapped token vault — the first three of `LibProdBeacons0_1_1`'s
    /// index order, excluding the orchestrator beacon.
    uint256 internal constant TOKEN_BEACON_COUNT = 3;

    /// @notice Pre-flight the EOA-owned beacons, broadcast the ownership
    /// transfers to the active chain's token-owner Safe, re-assert the
    /// Safe-owned state, and prove the Safe can operate each beacon.
    function run() external {
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address[4] memory beaconList = LibProdBeacons0_1_1.beacons();
        address[4] memory implList = LibProdBeacons0_1_1.implementations();

        // Pre-flight: this chain's IN-USE beacons are the 0.1.1 set. Base's
        // in-use beacons are its V1-generation addresses, so the (unused)
        // 0.1.1 beacons there are not production state and are not
        // migrated here.
        address[4] memory inUse = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        for (uint256 i = 0; i < TOKEN_BEACON_COUNT; i++) {
            if (inUse[i] != beaconList[i]) revert NotA0_1_1BootstrapChain(block.chainid);
        }

        // Pre-flight: every beacon is deployed, is the OZ UpgradeableBeacon,
        // is still owned by the deploy EOA, and points at its pinned impl.
        // Reverts with the relevant typed error on the first drift, before
        // any broadcast happens.
        for (uint256 i = 0; i < TOKEN_BEACON_COUNT; i++) {
            LibBeaconInvariants.assertBeaconInvariants(beaconList[i], LibProdDeployV4.BEACON_INITIAL_OWNER, implList[i]);
        }

        console2.log("Migrating token beacon owners on chain id", block.chainid);
        console2.log("from (deploy EOA):", LibProdDeployV4.BEACON_INITIAL_OWNER);
        console2.log("to (token-owner Safe):", safe);

        // Broadcast the ownership transfers from the EOA — three separate
        // transactions, one per beacon.
        vm.startBroadcast();
        for (uint256 i = 0; i < TOKEN_BEACON_COUNT; i++) {
            Ownable(beaconList[i]).transferOwnership(safe);
        }
        vm.stopBroadcast();

        // Post-state: every beacon is now Safe-owned, implementations
        // unchanged.
        for (uint256 i = 0; i < TOKEN_BEACON_COUNT; i++) {
            LibBeaconInvariants.assertBeaconInvariants(beaconList[i], safe, implList[i]);
        }

        // n+1: the Safe can drive each beacon through its threshold-gated
        // exec — an idempotent upgradeTo(currentImpl), simulated on the fork.
        for (uint256 i = 0; i < TOKEN_BEACON_COUNT; i++) {
            LibSafeOps.simulateBeaconNPlus1(
                IGnosisSafe(safe), beaconList[i], implList[i], LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
            );
        }

        console2.log("Transferred ownership of 3 token beacons to the Safe; n+1 upgrade path proven.");
    }
}
