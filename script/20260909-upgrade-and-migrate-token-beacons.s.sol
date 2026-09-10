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
import {LibClosureInvariants} from "../src/lib/LibClosureInvariants.sol";
import {LibSafeOps, IUpgradeableBeacon} from "../src/lib/LibSafeOps.sol";

/// @notice The active chain's in-use production beacons are not the
/// deterministic 0.1.1 set, so this bootstrap does not apply to it (Base
/// runs its V1-generation beacons, migrated by `MigrateBeaconOwners`).
/// @param chainId The active chain id.
error NotA0_1_1BootstrapChain(uint256 chainId);

/// @title UpgradeAndMigrateTokenBeacons
/// @notice Brings a freshly bootstrapped 0.1.1 chain's three ST0x production
/// token beacons (receipt, receipt vault, wrapped token vault) to the
/// cross-chain end state in ONE EOA broadcast, before any token exists on
/// the chain:
///
///   1. `upgradeTo(0.1.30)` on the receipt and receipt-vault beacons — the
///      same repoint `20260825-upgrade-fleet-to-0-1-30` authored for the
///      Safe on Base / Ethereum / HyperEVM, performed here by the deploy EOA
///      while it still owns the beacons;
///   2. `transferOwnership(safe)` on all three beacons, from the deploy EOA
///      (`LibProdDeployV4.BEACON_INITIAL_OWNER`, rainlang.eth) to the
///      chain's token-owner Safe.
///
/// The chain-generic successor of `20260716-migrate-beacon-owners-ethereum`
/// and `20260722-migrate-beacon-owners-hyperevm`, which each hardcoded one
/// chain and left the upgrade to a later Safe bundle: every chain that
/// bootstraps at 0.1.1 gets the SAME deterministic beacon set
/// (`LibProdBeacons0_1_1`), the beacon-set deployer constructors bake
/// `BEACON_INITIAL_OWNER` as the initial owner, and the audited 0.1.30
/// implementations are Zoltu-deterministic too — so the operation is
/// identical per chain and only the Safe differs. The Safe is resolved from
/// `block.chainid`, so a new chain is covered by its Safe pin alone.
///
/// Folding the upgrade into the ownership hand-off is what lets a new chain
/// reach parity with the executed fleet upgrade WITHOUT a Safe signature:
/// on the three existing chains the beacons already backed live vaults when
/// 0.1.30 shipped, so the repoint had to be a Safe-signed, state-preserving
/// bundle; on a fresh chain the beacons back nothing yet, so the EOA that
/// owns them can repoint them before handing them over, and the tokens are
/// then born on 0.1.30 through the 0.1.1 unified deployer (the proxy
/// address is a function of the deployer, never of what the beacon serves).
/// The wrapped-token-vault beacon is deliberately NOT repointed, matching
/// the fleet upgrade's scope: its 0.1.30 bytecode differs only by the
/// optimizer change, and the coordinated-release note in `CHANGELOG.md`
/// keeps it on 0.1.1.
///
/// The orchestrator beacon is deliberately NOT in scope either: it arrives
/// with the 0.1.30 closure, not the 0.1.1 suites, and has its own migration
/// (`20260818-migrate-orchestrator-beacon-owner`).
///
/// @dev This is an **EOA broadcast, not a Safe artifact and not a CI
/// deploy-key dispatch**: an `Ownable` beacon upgrades and transfers by its
/// current owner, and the current owner is the EOA — which is why this
/// script is absent from the `manual-broadcast.yaml` registry (that
/// dispatcher broadcasts as the CI deploy key). Broadcast as the EOA, once
/// per chain:
///
///   forge script script/20260909-upgrade-and-migrate-token-beacons.s.sol \
///     --rpc-url <network> --broadcast --private-key <EOA key>
///
/// (HyperEVM additionally needs `--legacy`.)
///
/// Ordering: run AFTER the 0.1.1 impl suites AND the 0.1.30 suites are
/// deployed on the chain (the beacons do not exist before the former; the
/// upgrade targets do not exist before the latter) and BEFORE the token
/// deploy — the `20260807-deploy-missing-tokens` pre-flight hard-gates on
/// `assertProdBeaconsOwnedByChainSafe`. The beacons back no vaults yet at
/// that point, so the upgrade is a pure repoint with no live-vault state to
/// preserve, and the hand-off carries no live-vault risk.
///
/// The flow is the beacon-owner-migration standard shape:
///
/// 1. **Pre-flight** — the active chain's in-use beacons must BE the 0.1.1
///    set (a chain on other beacons is refused); the audited 0.1.30 receipt,
///    receipt vault and corporate-actions facet (the new vault's
///    `fallback()` delegatecalls the facet — a code-less facet silently
///    no-ops) must be live at their pins by codehash; and each of the three
///    beacons is asserted in the EOA-owned state via
///    `LibBeaconInvariants.assertBeaconInvariants` (deployed, pinned OZ
///    `UpgradeableBeacon` codehash, EOA owner, pointing at its audited 0.1.1
///    implementation). A drifted or already-migrated beacon aborts before
///    any broadcast — re-running after execution reverts on the owner check
///    rather than doing anything.
/// 2. **Broadcast** — two `upgradeTo(0.1.30)` calls, then three
///    `transferOwnership(safe)` calls, all from the EOA. The upgrades come
///    first because the EOA can only perform them while it is still owner.
/// 3. **Post-state** — every beacon is re-asserted, now Safe-owned, the
///    receipt and receipt-vault beacons on their 0.1.30 implementations and
///    the wrapped-token-vault beacon unchanged on 0.1.1.
/// 4. **n+1 reversibility** — `LibSafeOps.simulateBeaconNPlus1` proves the
///    Safe can act on each beacon post-migration by routing an idempotent
///    `upgradeTo(currentImpl)` through the Safe's threshold-gated
///    `execTransaction`. Fork-local simulation, not broadcast.
contract UpgradeAndMigrateTokenBeacons is Script {
    /// @notice Number of token beacons migrated: receipt, receipt vault,
    /// wrapped token vault — the first three of `LibProdBeacons0_1_1`'s
    /// index order, excluding the orchestrator beacon.
    uint256 internal constant TOKEN_BEACON_COUNT = 3;

    /// @notice The implementation each token beacon serves once this script
    /// has executed: 0.1.30 for the receipt and receipt-vault beacons, the
    /// unchanged 0.1.1 for the wrapped-token-vault beacon. Index order is
    /// `LibProdBeacons0_1_1`'s.
    /// @return impls The post-execution implementation per token beacon.
    function postImplementations() internal pure returns (address[3] memory impls) {
        impls[LibBeaconInvariants.RECEIPT_BEACON_INDEX] = LibProdDeployV4.STOX_RECEIPT_0_1_30;
        impls[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX] = LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30;
        impls[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX] = LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1;
    }

    /// @notice The audited 0.1.30 upgrade targets (and the facet the new
    /// vault delegatecalls) must be live at their pins by codehash — the
    /// same gate `20260825-upgrade-fleet-to-0-1-30` applies before it
    /// authors the Safe bundle.
    function assertUpgradeTargetsLive() internal view {
        LibClosureInvariants.assertClosureContract(
            LibProdDeployV4.STOX_RECEIPT_0_1_30, LibProdDeployV4.STOX_RECEIPT_CODEHASH_0_1_30
        );
        LibClosureInvariants.assertClosureContract(
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30, LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_30
        );
        LibClosureInvariants.assertClosureContract(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_30,
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_0_1_30
        );
    }

    /// @notice Pre-flight the EOA-owned 0.1.1 beacons, broadcast the two
    /// 0.1.30 upgrades and the three ownership transfers to the active
    /// chain's token-owner Safe, re-assert the Safe-owned end state, and
    /// prove the Safe can operate each beacon.
    function run() external {
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address[4] memory beaconList = LibProdBeacons0_1_1.beacons();
        address[4] memory preImpls = LibProdBeacons0_1_1.implementations();
        address[3] memory postImpls = postImplementations();

        // Pre-flight: this chain's IN-USE beacons are the 0.1.1 set. Base's
        // in-use beacons are its V1-generation addresses, so the (unused)
        // 0.1.1 beacons there are not production state and are not
        // touched here.
        address[4] memory inUse = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        for (uint256 i = 0; i < TOKEN_BEACON_COUNT; i++) {
            if (inUse[i] != beaconList[i]) revert NotA0_1_1BootstrapChain(block.chainid);
        }

        // Pre-flight: the 0.1.30 targets the beacons will be pointed at are
        // live by codehash. Checked before the beacon state so a chain
        // missing the 0.1.30 suites is refused with the closure error, not
        // a misleading beacon error.
        assertUpgradeTargetsLive();

        // Pre-flight: every beacon is deployed, is the OZ UpgradeableBeacon,
        // is still owned by the deploy EOA, and points at its pinned 0.1.1
        // impl. Reverts with the relevant typed error on the first drift,
        // before any broadcast happens.
        for (uint256 i = 0; i < TOKEN_BEACON_COUNT; i++) {
            LibBeaconInvariants.assertBeaconInvariants(beaconList[i], LibProdDeployV4.BEACON_INITIAL_OWNER, preImpls[i]);
        }

        console2.log("Upgrading + migrating token beacons on chain id", block.chainid);
        console2.log("from (deploy EOA):", LibProdDeployV4.BEACON_INITIAL_OWNER);
        console2.log("to (token-owner Safe):", safe);

        // Broadcast from the EOA: the two upgrades first (only the current
        // owner can upgrade, and the EOA stops being owner below), then the
        // three ownership transfers. Five separate transactions.
        vm.startBroadcast();
        IUpgradeableBeacon(beaconList[LibBeaconInvariants.RECEIPT_BEACON_INDEX])
            .upgradeTo(postImpls[LibBeaconInvariants.RECEIPT_BEACON_INDEX]);
        IUpgradeableBeacon(beaconList[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX])
            .upgradeTo(postImpls[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]);
        for (uint256 i = 0; i < TOKEN_BEACON_COUNT; i++) {
            Ownable(beaconList[i]).transferOwnership(safe);
        }
        vm.stopBroadcast();

        // Post-state: every beacon is now Safe-owned; receipt + receipt
        // vault serve 0.1.30, wrapped token vault is unchanged on 0.1.1.
        for (uint256 i = 0; i < TOKEN_BEACON_COUNT; i++) {
            LibBeaconInvariants.assertBeaconInvariants(beaconList[i], safe, postImpls[i]);
        }

        // n+1: the Safe can drive each beacon through its threshold-gated
        // exec — an idempotent upgradeTo(currentImpl), simulated on the fork.
        for (uint256 i = 0; i < TOKEN_BEACON_COUNT; i++) {
            LibSafeOps.simulateBeaconNPlus1(
                IGnosisSafe(safe), beaconList[i], postImpls[i], LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
            );
        }

        console2.log(
            "Receipt + receipt-vault beacons on 0.1.30; ownership of 3 token beacons transferred to the Safe; n+1 upgrade path proven."
        );
    }
}
