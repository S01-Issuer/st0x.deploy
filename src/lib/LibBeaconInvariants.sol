// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {LibMigrationInvariant} from "./LibMigrationInvariant.sol";
import {LibOrchestratorInvariants} from "./LibOrchestratorInvariants.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";
import {LibProdBeaconsBase} from "./LibProdBeaconsBase.sol";
import {LibProdBeacons0_1_1} from "./LibProdBeacons0_1_1.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";

/// @notice Minimal `Ownable`-like surface used to read a beacon's owner.
/// Every OpenZeppelin `UpgradeableBeacon` exposes `owner()`; this library
/// only needs the getter, not the transfer/renounce mutators. Declared
/// inline here so the beacon invariant bundle owns its only ownership-read
/// surface rather than re-coupling to a Safe-side or token-side interface
/// that could drift.
interface IOwnable {
    /// @notice The current owner of the contract.
    /// @return The owner address.
    function owner() external view returns (address);
}

/// @notice The address supplied as a beacon has no runtime code. Either the
/// beacon was never deployed at this address or it has been
/// `SELFDESTRUCT`-ed. Caught first so later reads against the address are
/// only attempted once it is known to be a contract.
/// @param beacon The address that was expected to be a deployed beacon.
error BeaconNotDeployed(address beacon);

/// @notice The beacon's runtime codehash does not match the pinned OZ
/// `UpgradeableBeacon` bytecode
/// (`LibBeaconInvariants.UPGRADEABLE_BEACON_CODEHASH`). Signals either an
/// address swap or a look-alike contract shadowing the `implementation()` /
/// `owner()` selectors. The codehash pin is what lets the access-control
/// behaviour be trusted as OZ's audited bytecode rather than re-tested here.
/// @param beacon The beacon address whose codehash was checked.
/// @param expected The pinned `UpgradeableBeacon` codehash.
/// @param actual The codehash returned by `extcodehash(beacon)`.
error BeaconCodehashMismatch(address beacon, bytes32 expected, bytes32 actual);

/// @notice The beacon's `owner()` does not match the expected owner. Used
/// both to assert the pre-migration EOA owner and the post-migration Safe
/// owner; the caller supplies which one it expects because the owner is the
/// property the migration deliberately changes.
/// @param beacon The beacon address whose owner was read.
/// @param expected The owner address the caller expected.
/// @param actual The owner address returned by `Ownable(beacon).owner()`.
error BeaconOwnerMismatch(address beacon, address expected, address actual);

/// @notice The beacon's `implementation()` does not match the expected
/// implementation. The ownership migration must not change any beacon's
/// implementation, so this is asserted equal pre- and post-migration; the
/// upgrade script asserts it against the new implementation after the
/// upgrade.
/// @param beacon The beacon address whose implementation pointer was read.
/// @param expected The implementation address the caller expected.
/// @param actual The implementation address returned by
/// `IBeacon(beacon).implementation()`.
error BeaconImplementationMismatch(address beacon, address expected, address actual);

/// @notice The beacon's implementation pointer resolves to an address with
/// no runtime code. A beacon pointing at a code-less implementation would
/// brick every proxy that delegates through it, so this is surfaced as an
/// invariant break rather than discovered at the first proxy call.
/// @param beacon The beacon address whose implementation was inspected.
/// @param implementation The implementation address that has no code.
error BeaconImplNotDeployed(address beacon, address implementation);

/// @notice No in-use production beacon set is pinned for the active chain.
/// Deliberately a typed revert rather than a silent fallback to another
/// chain's beacons: asserting against beacons production doesn't run on is
/// exactly the dead-state pinning this map exists to prevent.
/// @param chainId The chain id with no pinned in-use beacon set.
error UnsupportedChainForProdBeacons(uint256 chainId);

/// @title LibBeaconInvariants
/// @notice Reusable invariant assertions for an OpenZeppelin
/// `UpgradeableBeacon`. The single public assertion either returns silently
/// when the invariant holds against the live chain state or reverts with a
/// typed error that pinpoints the drift.
/// @dev Extracted from `LibSafeInvariants` because a beacon is an OZ
/// `UpgradeableBeacon`, not a Safe: the beacon checks share none of the
/// Safe v1.4.1 storage-slot pins and have no business living in a
/// Safe-named library. Keeping them here means the beacon-ownership
/// migration and the receipt vault upgrade reach into a library named for
/// what it actually validates.
library LibBeaconInvariants {
    /// @notice The CURRENT owner of the three V1 production beacons on Base
    /// — the single source of truth for "who owns the prod beacons today".
    /// Every consumer that means "the current beacon owner" (post-state
    /// asserts, upgrade pre-flights, `vm.prank` targets in fork tests)
    /// reads this constant, so an ownership change is a one-line edit here
    /// rather than a sweep of hardcoded call sites.
    ///
    /// The ST0x token-owner Safe since the `MigrateBeaconOwners` broadcast
    /// executed on Base (2026-07); the deploy-time EOA before that. Sites
    /// that deliberately mean the deploy-time initial owner (un-migrated
    /// V4-generation beacons, the migration's reconstructed pre-state) use
    /// `LibProdDeployV1.BEACON_INITIAL_OWNER` / the V4 lib's
    /// `BEACON_INITIAL_OWNER` instead — do not conflate the two.
    address internal constant PROD_BEACON_OWNER = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;

    /// @notice Runtime codehash shared by every OpenZeppelin
    /// `UpgradeableBeacon` instance on Base. An `UpgradeableBeacon` keeps its
    /// implementation pointer and owner in storage rather than in code, so the
    /// runtime bytecode is identical across every beacon constructed from the
    /// same `UpgradeableBeacon` source. Pinning this codehash lets a beacon
    /// invariant assert that `implementation()` / `owner()` are serviced by
    /// the canonical OZ beacon bytecode — whose access-control behaviour is
    /// then guaranteed by OZ's own audit — rather than a look-alike contract
    /// shadowing those selectors.
    /// @dev Equal to
    /// `LibProdDeployV1.PROD_BEACON_BASE_RUNTIME_CODEHASH_V1`; re-declared
    /// here so the beacon invariant does not have to reach into the V1 deploy
    /// library. Verified on Base on 2026-05-22 against the three live V1
    /// beacons (receipt, receipt vault, wrapped token vault), all of which
    /// share this codehash.
    ///
    /// This value is NOT a property of the OZ source alone, whatever an
    /// earlier revision of this comment claimed. It is the runtime of one
    /// build: OZ's `UpgradeableBeacon` as compiled for the V1 generation, at
    /// the optimizer settings of that day. `optimizer_runs` has since moved
    /// 5000 -> 2000, so a beacon compiled from today's tree is 728 bytes
    /// against these 858 and cannot match. Pin a NEW constant per generation;
    /// never repoint this one, which the live V1 fleet is still asserted
    /// against.
    bytes32 internal constant UPGRADEABLE_BEACON_CODEHASH =
        0x8e95867e52db417944afd90f3b6c3c980962831e8a944e7f6958ba8f8cc10630;

    /// @notice Runtime codehash of OZ `UpgradeableBeacon` as compiled by the
    /// CURRENT tree — OpenZeppelin 5.6.1 at `optimizer_runs = 2000`. This is
    /// the beacon `ST0xOrchestratorBeaconSetDeployer`'s constructor builds,
    /// so it is what the orchestrator beacon must be asserted against.
    /// @dev Re-derived by `testOrchestratorBeaconCodehashPin`, which compiles
    /// a beacon and compares. That test is the whole guarantee: without it
    /// this constant silently rots the next time OZ or the optimizer moves,
    /// which is exactly how the V1 pin came to be asserted against a beacon
    /// that could never match it.
    bytes32 internal constant UPGRADEABLE_BEACON_CODEHASH_0_1_30 =
        0x448cd06335de9e79ecdc51aa7c6647926860a1976f407de6f79f363b85ccaf2b;

    /// @notice Assert the invariants of an OpenZeppelin `UpgradeableBeacon`
    /// at `beacon`: it is a deployed contract, its runtime codehash matches
    /// the pinned OZ `UpgradeableBeacon` bytecode, its `owner()` matches
    /// `expectedOwner`, its `implementation()` matches `expectedImpl`, and
    /// that implementation is itself deployed. Reverts with a typed error on
    /// first failure; returns silently otherwise.
    /// @dev Generic over any beacon (V1, V2, or future) so the same helper
    /// serves the beacon-ownership migration pre/post-flight and the receipt
    /// vault upgrade pre/post-flight. The owner and implementation are
    /// caller-supplied because both are properties an operational script
    /// deliberately mutates: the ownership migration changes the owner from
    /// the EOA to the Safe, and the V3 upgrade changes the implementation.
    ///
    /// The codehash pin (check #2) is the load-bearing invariant. OZ's
    /// `UpgradeableBeacon` ships the access control (`onlyOwner` on
    /// `upgradeTo`, `Ownable` transfer/renounce semantics) that this
    /// deployment relies on; pinning the bytecode means that behaviour is
    /// guaranteed by OZ's audit rather than re-tested in this repo. A
    /// beacon whose codehash matches by definition behaves like the OZ
    /// beacon, so no behavioural access-control assertions are duplicated
    /// here.
    ///
    /// Check ordering mirrors `LibSafeInvariants.assertImmutableInvariants`:
    /// code presence first (cheapest, and catches an EOA or empty address),
    /// codehash second (catches a look-alike), then the storage-backed reads
    /// (`owner()`, `implementation()`) once the bytecode is proven to be the
    /// OZ beacon, and the implementation code-presence check last because it
    /// depends on the implementation read having succeeded.
    /// @param beacon The beacon to assert invariants on.
    /// @param expectedOwner The owner the beacon is expected to report.
    /// @param expectedImpl The implementation the beacon is expected to
    /// point at.
    function assertBeaconInvariants(address beacon, address expectedOwner, address expectedImpl) internal view {
        assertBeaconInvariants(beacon, expectedOwner, expectedImpl, UPGRADEABLE_BEACON_CODEHASH);
    }

    /// @notice As `assertBeaconInvariants`, for a beacon of a generation other
    /// than V1.
    /// @dev The codehash is a parameter because it belongs to a build, not to
    /// the OZ source: the V1 fleet and the 0.1.30 orchestrator beacon are both
    /// canonical OZ `UpgradeableBeacon`s and their runtimes still differ. A
    /// single hardcoded pin forced every caller onto V1's, which made the
    /// orchestrator migration revert `BeaconCodehashMismatch` in pre-flight on
    /// every chain.
    /// @param beacon The beacon to assert.
    /// @param expectedOwner The address `owner()` must return.
    /// @param expectedImpl The address `implementation()` must return.
    /// @param expectedCodehash The runtime codehash for this beacon's build.
    function assertBeaconInvariants(
        address beacon,
        address expectedOwner,
        address expectedImpl,
        bytes32 expectedCodehash
    ) internal view {
        if (beacon.code.length == 0) {
            revert BeaconNotDeployed(beacon);
        }

        bytes32 actualCodehash;
        assembly ("memory-safe") {
            actualCodehash := extcodehash(beacon)
        }
        if (actualCodehash != expectedCodehash) {
            revert BeaconCodehashMismatch(beacon, expectedCodehash, actualCodehash);
        }

        address actualOwner = IOwnable(beacon).owner();
        if (actualOwner != expectedOwner) {
            revert BeaconOwnerMismatch(beacon, expectedOwner, actualOwner);
        }

        address actualImpl = IBeacon(beacon).implementation();
        if (actualImpl != expectedImpl) {
            revert BeaconImplementationMismatch(beacon, expectedImpl, actualImpl);
        }

        if (actualImpl.code.length == 0) {
            revert BeaconImplNotDeployed(beacon, actualImpl);
        }
    }

    /// @notice Position of the receipt beacon in `prodBeaconsForChainId`.
    uint256 internal constant RECEIPT_BEACON_INDEX = 0;

    /// @notice Position of the receipt-vault beacon in `prodBeaconsForChainId`.
    uint256 internal constant RECEIPT_VAULT_BEACON_INDEX = 1;

    /// @notice Position of the wrapped-token-vault beacon in
    /// `prodBeaconsForChainId`.
    uint256 internal constant WRAPPED_TOKEN_VAULT_BEACON_INDEX = 2;

    /// @notice Position of the orchestrator beacon in `prodBeaconsForChainId`.
    uint256 internal constant ORCHESTRATOR_BEACON_INDEX = 3;

    /// @notice Expected runtime codehash of each beacon in
    /// `prodBeaconsForChainId`, index-aligned with it.
    /// @dev The set spans two build generations and a single pin cannot cover
    /// both: the three token beacons are the V1 build (858 bytes), the
    /// orchestrator beacon is OZ 5.6.1 at the current `optimizer_runs`
    /// (728 bytes). Asserting the whole set against one constant reverts on
    /// the orchestrator beacon and takes every chain's migration with it.
    /// @return The expected codehash per beacon.
    function prodBeaconCodehashesForChainId(uint256) internal pure returns (bytes32[4] memory) {
        return [
            UPGRADEABLE_BEACON_CODEHASH,
            UPGRADEABLE_BEACON_CODEHASH,
            UPGRADEABLE_BEACON_CODEHASH,
            UPGRADEABLE_BEACON_CODEHASH_0_1_30
        ];
    }

    /// @notice The three production beacons IN USE on the active chain, in a
    /// fixed order (receipt, receipt vault, wrapped token vault). Beacon
    /// addresses are per-chain deploy artifacts that never change once a
    /// chain's production tokens point at them — only the implementations they
    /// serve are upgraded — so "which beacons is production running on" is
    /// per-chain pinned state. Each chain's set lives in its own lib
    /// (`LibProdBeaconsBase` / `LibProdBeacons0_1_1`, same shape and index
    /// order); this map only dispatches by chain id.
    /// @param chainId The active chain id (`block.chainid`).
    /// @return The chain's three in-use beacon addresses.
    function prodBeaconsForChainId(uint256 chainId) internal view returns (address[4] memory) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) {
            return LibProdBeaconsBase.beacons();
        }
        if (chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            return LibProdBeacons0_1_1.beacons();
        }
        if (chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID) {
            // HyperEVM bootstraps at 0.1.1 too — the deterministic beacon
            // set resolves to the SAME addresses as Ethereum's.
            return LibProdBeacons0_1_1.beacons();
        }
        revert UnsupportedChainForProdBeacons(chainId);
    }

    /// @notice Assert the active chain's three IN-USE production beacons are
    /// deployed and owned by THAT chain's token-owner Safe. This is the
    /// ownership invariant that matters operationally: whoever owns an in-use
    /// beacon can repoint every production vault proxy on the chain, so each
    /// chain's live beacons must be held by its Safe — no EOA, no other
    /// chain's Safe. Where the beacons POINT is deliberately not asserted
    /// here; implementation parity across chains is the cross-chain parity
    /// pin's concern.
    /// @param chainId The active chain id (`block.chainid`).
    function assertProdBeaconsOwnedByChainSafe(uint256 chainId) internal view {
        assertProdBeaconsOwnedBy(chainId, LibSafeInvariants.safeForChainId(chainId));
    }

    /// @notice Owner-parametric `assertProdBeaconsOwnedByChainSafe`: assert
    /// the active chain's three IN-USE production beacons are deployed and
    /// owned by `expectedOwner`. Parameterised because the beacon owner is a
    /// principal an operational script deliberately mutates — the
    /// governance-timelock migration moves it from the chain's Safe to the
    /// chain's timelock — so the same iteration serves the pre-state
    /// (Safe-owned), the post-state (timelock-owned), and the pre-flight of
    /// the migration that moves it.
    /// Each beacon's runtime codehash is pinned to the OZ
    /// `UpgradeableBeacon` bytecode BEFORE its `owner()` read is trusted —
    /// the same trust order the migration script's selection applies, and
    /// for the same reason: a look-alike contract can shadow the `owner()`
    /// selector and report whatever owner passes this check.
    /// @param chainId The active chain id (`block.chainid`).
    /// @param expectedOwner The address every in-use beacon must report as
    /// `owner()`.
    function assertProdBeaconsOwnedBy(uint256 chainId, address expectedOwner) internal view {
        address[4] memory beacons = prodBeaconsForChainId(chainId);
        bytes32[4] memory codehashes = prodBeaconCodehashesForChainId(chainId);
        for (uint256 i = 0; i < beacons.length; i++) {
            _assertDeployedPinnedBeacon(beacons[i], codehashes[i]);
            address actualOwner = IOwnable(beacons[i]).owner();
            // The orchestrator beacon joins the governed set mid-lifecycle:
            // its constructor bakes the deploy EOA as owner and the
            // `20260818-migrate-orchestrator-beacon-owner` EOA broadcast
            // moves it to the chain's Safe. Until that migration's deadline,
            // the EOA is an accepted pre-state; after it, only the expected
            // owner passes — the same window `LibOrchestratorInvariants.
            // assertBeaconSet` applies.
            if (
                i == ORCHESTRATOR_BEACON_INDEX && actualOwner == LibProdDeployV4.BEACON_INITIAL_OWNER
                    && block.timestamp < LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON_OWNER_MIGRATION_DEADLINE
            ) {
                continue;
            }
            if (actualOwner != expectedOwner) {
                revert BeaconOwnerMismatch(beacons[i], expectedOwner, actualOwner);
            }
        }
    }

    /// @notice Migration-window variant of `assertProdBeaconsOwnedBy`: every
    /// in-use production beacon on the chain must report `pre` OR `post` as
    /// `owner()` before `deadline`, and exactly `post` at/after it.
    ///
    /// The beacon leg is the load-bearing half of the governance-timelock
    /// migration. Whoever owns an in-use beacon can `upgradeTo` a new
    /// implementation for EVERY production proxy on the chain in a single
    /// transaction — which would let them re-take vault ownership and
    /// rewrite the authoriser wiring outright. Leaving the beacons on the
    /// Safe while vault ownership sits behind the timelock would make the
    /// delay bypassable by design, so this surface migrates in the same
    /// bundle and is forced by the same deadline.
    /// @dev Mirrors `LibTokenInvariants.assertUniformOwnershipMigration` —
    /// same two-valued window, same drift semantics (any third owner trips
    /// `MigrationStateDrift` immediately, deadline notwithstanding). Each
    /// beacon's runtime codehash is pinned to the OZ `UpgradeableBeacon`
    /// bytecode BEFORE its `owner()` read is trusted, on the same grounds
    /// as `assertProdBeaconsOwnedBy`: this is the cron-facing drift
    /// detector for the surface, and a look-alike beacon shadowing
    /// `owner()` must surface as a codehash break, not pass as migrated.
    /// Where the beacons POINT is deliberately not asserted here; the
    /// migration script pins implementation immutability across its own
    /// bundle, and cross-chain implementation parity is the parity pin's
    /// concern.
    /// @param chainId The active chain id (`block.chainid`).
    /// @param pre The accepted beacon owner before the migration runs.
    /// @param post The accepted beacon owner after the migration runs.
    /// @param deadline Unix timestamp past which only `post` is accepted.
    function assertProdBeaconsOwnershipMigration(uint256 chainId, address pre, address post, uint256 deadline)
        internal
        view
    {
        address[4] memory beacons = prodBeaconsForChainId(chainId);
        bytes32[4] memory codehashes = prodBeaconCodehashesForChainId(chainId);
        for (uint256 i = 0; i < beacons.length; i++) {
            _assertDeployedPinnedBeacon(beacons[i], codehashes[i]);
            address actualOwner = IOwnable(beacons[i]).owner();
            // See `assertProdBeaconsOwnedBy`: the orchestrator beacon's own
            // EOA -> Safe migration window overlaps the governance window,
            // so its baked initial owner is an accepted extra pre-state
            // until that migration's deadline.
            if (
                i == ORCHESTRATOR_BEACON_INDEX && actualOwner == LibProdDeployV4.BEACON_INITIAL_OWNER
                    && block.timestamp < LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON_OWNER_MIGRATION_DEADLINE
            ) {
                continue;
            }
            LibMigrationInvariant.assertMigration("beacon.owner()", actualOwner, pre, post, deadline);
        }
    }

    /// @notice Deployment + codehash gate shared by the in-use-beacon
    /// sweeps: the address must carry runtime code, and that code must be
    /// the pinned OZ `UpgradeableBeacon` bytecode. Runs before any
    /// `owner()` read is trusted — a look-alike contract could shadow the
    /// selector and report whatever owner passes the caller's check, so
    /// the pin is what makes the subsequent read meaningful.
    /// @param beacon The beacon to gate.
    function _assertDeployedPinnedBeacon(address beacon, bytes32 expectedCodehash) private view {
        if (beacon.code.length == 0) {
            revert BeaconNotDeployed(beacon);
        }
        bytes32 actualCodehash = beacon.codehash;
        if (actualCodehash != expectedCodehash) {
            revert BeaconCodehashMismatch(beacon, expectedCodehash, actualCodehash);
        }
    }
}
