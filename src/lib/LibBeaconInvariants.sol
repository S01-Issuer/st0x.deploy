// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {LibMigrationInvariant} from "./LibMigrationInvariant.sol";
import {LibProdBeaconsBase} from "./LibProdBeaconsBase.sol";
import {LibProdBeacons0_1_1} from "./LibProdBeacons0_1_1.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";

/// @notice Minimal `Ownable`-like surface used to read a beacon's owner:
/// the `owner()` getter every OpenZeppelin `UpgradeableBeacon` exposes.
interface IOwnable {
    /// @notice The current owner of the contract.
    /// @return The owner address.
    function owner() external view returns (address);
}

/// @notice The address supplied as a beacon has no runtime code. Checked
/// first so later reads against the address are only attempted once it is
/// known to be a contract.
/// @param beacon The address that was expected to be a deployed beacon.
error BeaconNotDeployed(address beacon);

/// @notice The beacon's runtime codehash does not match the pinned OZ
/// `UpgradeableBeacon` bytecode for its build.
/// @param beacon The beacon address whose codehash was checked.
/// @param expected The pinned `UpgradeableBeacon` codehash.
/// @param actual The codehash returned by `extcodehash(beacon)`.
error BeaconCodehashMismatch(address beacon, bytes32 expected, bytes32 actual);

/// @notice The beacon's `owner()` does not match the expected owner.
/// @param beacon The beacon address whose owner was read.
/// @param expected The owner address the caller expected.
/// @param actual The owner address returned by `Ownable(beacon).owner()`.
error BeaconOwnerMismatch(address beacon, address expected, address actual);

/// @notice The beacon's `implementation()` does not match the expected
/// implementation.
/// @param beacon The beacon address whose implementation pointer was read.
/// @param expected The implementation address the caller expected.
/// @param actual The implementation address returned by
/// `IBeacon(beacon).implementation()`.
error BeaconImplementationMismatch(address beacon, address expected, address actual);

/// @notice The beacon's implementation pointer resolves to an address with
/// no runtime code; every proxy delegating through the beacon would revert.
/// @param beacon The beacon address whose implementation was inspected.
/// @param implementation The implementation address that has no code.
error BeaconImplNotDeployed(address beacon, address implementation);

/// @notice No in-use production beacon set is pinned for the active chain.
/// @param chainId The chain id with no pinned in-use beacon set.
error UnsupportedChainForProdBeacons(uint256 chainId);

/// @title LibBeaconInvariants
/// @notice Invariant assertions for an OpenZeppelin `UpgradeableBeacon`.
/// Each assertion either returns silently when the invariant holds against
/// the live chain state or reverts with a typed error that pinpoints the
/// drift.
library LibBeaconInvariants {
    /// @notice The owner of the three V1 production beacons on Base: the
    /// ST0x token-owner Safe. Sites that mean the deploy-time initial owner
    /// use `LibProdDeployV1.BEACON_INITIAL_OWNER` / the V4 lib's
    /// `BEACON_INITIAL_OWNER` instead.
    address internal constant PROD_BEACON_OWNER = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;

    /// @notice Runtime codehash shared by the three V1 production beacons on
    /// Base. An `UpgradeableBeacon` keeps its implementation pointer and
    /// owner in storage rather than in code, so the runtime bytecode is
    /// identical across every beacon constructed from the same build.
    /// @dev Equal to `LibProdDeployV1.PROD_BEACON_BASE_RUNTIME_CODEHASH_V1`.
    ///
    /// This is the runtime of one build: OZ's `UpgradeableBeacon` as compiled
    /// for the V1 generation, 858 bytes. A beacon compiled from the current
    /// tree (`optimizer_runs = 2000`) is 728 bytes and cannot match. Each
    /// build generation has its own constant; this one is what the live V1
    /// fleet is asserted against.
    bytes32 internal constant UPGRADEABLE_BEACON_CODEHASH =
        0x8e95867e52db417944afd90f3b6c3c980962831e8a944e7f6958ba8f8cc10630;

    /// @notice Runtime codehash of OZ `UpgradeableBeacon` as compiled by the
    /// current tree, OpenZeppelin 5.6.1 at `optimizer_runs = 2000`. This is
    /// the beacon `ST0xOrchestratorBeaconSetDeployer`'s constructor builds,
    /// so it is what the orchestrator beacon is asserted against.
    /// @dev Re-derived by `testOrchestratorBeaconCodehashPin`, which compiles
    /// a beacon and compares.
    bytes32 internal constant UPGRADEABLE_BEACON_CODEHASH_0_1_30 =
        0x448cd06335de9e79ecdc51aa7c6647926860a1976f407de6f79f363b85ccaf2b;

    /// @notice Assert the invariants of a V1-build OpenZeppelin
    /// `UpgradeableBeacon` at `beacon`: it is a deployed contract, its runtime
    /// codehash matches `UPGRADEABLE_BEACON_CODEHASH`, its `owner()` matches
    /// `expectedOwner`, its `implementation()` matches `expectedImpl`, and
    /// that implementation is itself deployed. Reverts with a typed error on
    /// first failure; returns silently otherwise.
    /// @dev The owner and implementation are caller-supplied; both are
    /// properties an operational script mutates.
    ///
    /// The codehash pin is the load-bearing check: a beacon whose codehash
    /// matches runs OZ's `UpgradeableBeacon` access control (`onlyOwner` on
    /// `upgradeTo`, `Ownable` transfer/renounce), so no behavioural
    /// access-control assertions are duplicated here.
    ///
    /// Check order: code presence first, codehash second, then the
    /// storage-backed reads (`owner()`, `implementation()`), and the
    /// implementation code-presence check last.
    /// @param beacon The beacon to assert invariants on.
    /// @param expectedOwner The owner the beacon is expected to report.
    /// @param expectedImpl The implementation the beacon is expected to
    /// point at.
    function assertBeaconInvariants(address beacon, address expectedOwner, address expectedImpl) internal view {
        assertBeaconInvariants(beacon, expectedOwner, expectedImpl, UPGRADEABLE_BEACON_CODEHASH);
    }

    /// @notice As `assertBeaconInvariants`, for a beacon of any build
    /// generation.
    /// @dev The codehash belongs to a build, not to the OZ source: the V1
    /// fleet and the 0.1.30 orchestrator beacon are both OZ
    /// `UpgradeableBeacon`s with different runtimes.
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
    /// @dev The set spans two build generations: the three token beacons are
    /// the V1 build (858 bytes), the orchestrator beacon is OZ 5.6.1 at the
    /// current `optimizer_runs` (728 bytes).
    /// @return The expected codehash per beacon.
    function prodBeaconCodehashesForChainId(uint256) internal pure returns (bytes32[4] memory) {
        return [
            UPGRADEABLE_BEACON_CODEHASH,
            UPGRADEABLE_BEACON_CODEHASH,
            UPGRADEABLE_BEACON_CODEHASH,
            UPGRADEABLE_BEACON_CODEHASH_0_1_30
        ];
    }

    /// @notice The four production beacons in use on the active chain, in a
    /// fixed order (receipt, receipt vault, wrapped token vault,
    /// orchestrator), index-aligned with the `*_BEACON_INDEX` constants
    /// above. Each chain's set lives in its own lib (`LibProdBeaconsBase` /
    /// `LibProdBeacons0_1_1`, same shape and index order); this map
    /// dispatches by chain id.
    /// @param chainId The active chain id (`block.chainid`).
    /// @return The chain's four in-use beacon addresses.
    function prodBeaconsForChainId(uint256 chainId) internal view returns (address[4] memory) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) {
            return LibProdBeaconsBase.beacons();
        }
        // Ethereum, HyperEVM, Robinhood Chain and BNB Smart Chain run the
        // same deterministic 0.1.1 beacon set.
        if (chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            return LibProdBeacons0_1_1.beacons();
        }
        if (chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID) {
            return LibProdBeacons0_1_1.beacons();
        }
        if (chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID) {
            return LibProdBeacons0_1_1.beacons();
        }
        if (chainId == LibSafeInvariants.BSC_CHAIN_ID) {
            return LibProdBeacons0_1_1.beacons();
        }
        revert UnsupportedChainForProdBeacons(chainId);
    }

    /// @notice Assert the active chain's four in-use production beacons are
    /// deployed and owned by that chain's token-owner Safe. Whoever owns an
    /// in-use beacon can repoint every production vault proxy on the chain.
    /// Where the beacons point is not asserted here; implementation parity
    /// across chains is the cross-chain parity pin's concern.
    /// @param chainId The active chain id (`block.chainid`).
    function assertProdBeaconsOwnedByChainSafe(uint256 chainId) internal view {
        assertProdBeaconsOwnedBy(chainId, LibSafeInvariants.safeForChainId(chainId));
    }

    /// @notice Owner-parametric `assertProdBeaconsOwnedByChainSafe`: assert
    /// the active chain's four in-use production beacons are deployed and
    /// owned by `expectedOwner`. Each beacon's runtime codehash is pinned to
    /// the OZ `UpgradeableBeacon` bytecode before its `owner()` read is
    /// trusted.
    /// @param chainId The active chain id (`block.chainid`).
    /// @param expectedOwner The address every in-use beacon must report as
    /// `owner()`.
    function assertProdBeaconsOwnedBy(uint256 chainId, address expectedOwner) internal view {
        address[4] memory beacons = prodBeaconsForChainId(chainId);
        bytes32[4] memory codehashes = prodBeaconCodehashesForChainId(chainId);
        for (uint256 i = 0; i < beacons.length; i++) {
            _assertDeployedPinnedBeacon(beacons[i], codehashes[i]);
            address actualOwner = IOwnable(beacons[i]).owner();
            if (actualOwner != expectedOwner) {
                revert BeaconOwnerMismatch(beacons[i], expectedOwner, actualOwner);
            }
        }
    }

    /// @notice Migration-window variant of `assertProdBeaconsOwnedBy`: every
    /// in-use production beacon on the chain must report `pre` or `post` as
    /// `owner()` before `deadline`, and exactly `post` at/after it. Whoever
    /// owns an in-use beacon can `upgradeTo` a new implementation for every
    /// production proxy on the chain in a single transaction, so the beacons
    /// migrate to the timelock in the same bundle as vault ownership, under
    /// the same deadline.
    /// @dev Mirrors `LibTokenInvariants.assertUniformOwnershipMigration`:
    /// same two-valued window, same drift semantics (any third owner reverts
    /// with `MigrationStateDrift` regardless of the deadline). Each beacon's
    /// runtime codehash is pinned to the OZ `UpgradeableBeacon` bytecode
    /// before its `owner()` read is trusted. Where the beacons point is not
    /// asserted here.
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
            LibMigrationInvariant.assertMigration("beacon.owner()", actualOwner, pre, post, deadline);
        }
    }

    /// @notice Deployment + codehash gate shared by the in-use-beacon
    /// sweeps: the address must carry runtime code, and that code must be
    /// the pinned OZ `UpgradeableBeacon` bytecode. Runs before any
    /// `owner()` read is trusted.
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
