// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
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
    /// library for a value that is a property of the OZ bytecode rather than
    /// of any one deployment generation. Verified on Base on 2026-05-22
    /// against the three live V1 beacons (receipt, receipt vault, wrapped
    /// token vault), all of which share this codehash.
    bytes32 internal constant UPGRADEABLE_BEACON_CODEHASH =
        0x8e95867e52db417944afd90f3b6c3c980962831e8a944e7f6958ba8f8cc10630;

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
        if (beacon.code.length == 0) {
            revert BeaconNotDeployed(beacon);
        }

        bytes32 actualCodehash;
        assembly ("memory-safe") {
            actualCodehash := extcodehash(beacon)
        }
        if (actualCodehash != UPGRADEABLE_BEACON_CODEHASH) {
            revert BeaconCodehashMismatch(beacon, UPGRADEABLE_BEACON_CODEHASH, actualCodehash);
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
}
