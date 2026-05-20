// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IGnosisSafe} from "../interface/IGnosisSafe.sol";
import {LibProdSafes} from "./LibProdSafes.sol";

/// @notice The runtime codehash at the Safe's address does not match the
/// pinned Safe v1.4.1 L2 proxy codehash. Signals either that the address has
/// been swapped under us or that the Safe singleton has been redeployed with
/// different bytecode.
/// @param safe The Safe address whose codehash was checked.
/// @param expected The pinned codehash that was expected
/// (`LibProdSafes.SAFE_V1_4_1_L2_PROXY_CODEHASH`).
/// @param actual The codehash returned by `extcodehash(safe)`.
error SafeProxyCodehashMismatch(address safe, bytes32 expected, bytes32 actual);

/// @notice The implementation pointer stored at Safe storage slot `0x0` does
/// not match the pinned Safe v1.4.1 L2 singleton address. Used to detect a
/// `setImplementation`-style takeover that would route every call through a
/// different singleton.
/// @param safe The Safe proxy address that was inspected.
/// @param expected The pinned singleton address
/// (`LibProdSafes.SAFE_V1_4_1_L2_SINGLETON`).
/// @param actual The singleton address read from slot `0x0` of the proxy.
error SafeSingletonMismatch(address safe, address expected, address actual);

/// @notice The Safe singleton's `VERSION()` selector returned a string other
/// than `"1.4.1"`. This is a defence-in-depth check against the codehash and
/// singleton-slot pins: it cross-references the version the implementation
/// reports about itself with the codehash we expect.
/// @param safe The Safe address whose `VERSION()` was queried.
/// @param expected The expected version string (`"1.4.1"`).
/// @param actual The version string returned by the live Safe.
error SafeVersionMismatch(address safe, string expected, string actual);

/// @notice The Safe has at least one module enabled. The ST0x production Safe
/// is expected to have an empty module list; modules can bypass the threshold
/// requirement entirely and so are explicitly prohibited.
/// @param safe The Safe address whose module list was paginated.
/// @param firstModule The first module discovered in the paginated list.
error SafeUnexpectedModules(address safe, address firstModule);

/// @notice The Safe has a transaction guard installed. The ST0x production
/// Safe is expected to run without a guard; a guard can both block and
/// silently mutate transactions and so is explicitly prohibited.
/// @param safe The Safe address whose guard slot was read.
/// @param guard The guard address read from the well-known guard slot.
error SafeUnexpectedGuard(address safe, address guard);

/// @notice The Safe's fallback handler does not point at the pinned Safe
/// v1.4.1 CompatibilityFallbackHandler. A swapped fallback handler can shadow
/// any selector not implemented on the singleton (including view selectors
/// used for introspection) so the pin is enforced as an invariant.
/// @param safe The Safe address whose fallback handler slot was read.
/// @param expected The pinned fallback handler address
/// (`LibProdSafes.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER`).
/// @param actual The fallback handler address read from the well-known
/// fallback handler slot.
error SafeFallbackHandlerMismatch(address safe, address expected, address actual);

/// @notice The Safe's `getOwners()` array length does not match the
/// caller-supplied `expected` array length.
/// @param safe The Safe address whose owner set was queried.
/// @param expectedLength The owner count the caller expected.
/// @param actualLength The owner count returned by `getOwners()`.
error SafeOwnerCountMismatch(address safe, uint256 expectedLength, uint256 actualLength);

/// @notice The Safe's `getOwners()` returned an owner at `index` that does
/// not match the caller-supplied `expected` array at the same index. The
/// owner list is checked in Safe-internal linked-list order; reordering
/// without a roster change therefore still trips this error.
/// @param safe The Safe address whose owner set was queried.
/// @param index The zero-based index in the owner list that mismatched.
/// @param expectedOwner The owner address the caller expected at `index`.
/// @param actualOwner The owner address returned by `getOwners()` at `index`.
error SafeOwnerMismatch(address safe, uint256 index, address expectedOwner, address actualOwner);

/// @notice The Safe's `getThreshold()` does not match the caller-supplied
/// `expected` threshold.
/// @param safe The Safe address whose threshold was queried.
/// @param expected The threshold the caller expected.
/// @param actual The threshold returned by `getThreshold()`.
error SafeThresholdMismatch(address safe, uint256 expected, uint256 actual);

/// @title LibSafeInvariants
/// @notice Reusable invariant assertions for a Safe v1.4.1 L2 multisig
/// pinned to the ST0x token-owner deployment. Each public assertion either
/// returns silently when the invariant holds against the live chain state
/// or reverts with a typed error that pinpoints the drift.
/// @dev The library is consumed by the RAI-296 migration script (and
/// post-migration drift tests) as a single chokepoint for "is this Safe
/// still the Safe we think it is?" checks. Centralising the assertions here
/// keeps drift detection consistent across the script, its tests, and any
/// future migrations: anyone extending the Safe touch-points only needs to
/// add new invariants in one place.
///
/// All storage-slot constants come from the Safe v1.4.1 source:
/// https://github.com/safe-global/safe-contracts/tree/v1.4.1/contracts
/// Singleton (master copy) lives at slot `0x0` of the proxy by virtue of
/// `SafeProxy`'s minimal storage layout; the guard slot and fallback handler
/// slot are explicit constants in `GuardManager`/`FallbackManager` chosen so
/// they cannot collide with the owner/module/threshold linked-list slots.
library LibSafeInvariants {
    /// @notice Storage slot at which Safe v1.4.1 stores the transaction
    /// guard address. Equal to
    /// `keccak256("guard_manager.guard.address")`. A non-zero value here
    /// means a guard contract is intercepting `execTransaction`; the ST0x
    /// production Safe is required to have no guard.
    /// @dev Source: `GuardManager` in
    /// `safe-contracts/contracts/base/GuardManager.sol` at the v1.4.1 tag.
    bytes32 internal constant SAFE_GUARD_STORAGE_SLOT =
        0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    /// @notice Storage slot at which Safe v1.4.1 stores the fallback handler
    /// address. Equal to
    /// `keccak256("fallback_manager.handler.address")`. The address read
    /// here is the contract whose code services unknown selectors that fall
    /// through to the Safe proxy's `fallback`.
    /// @dev Source: `FallbackManager` in
    /// `safe-contracts/contracts/base/FallbackManager.sol` at the v1.4.1
    /// tag.
    bytes32 internal constant SAFE_FALLBACK_HANDLER_STORAGE_SLOT =
        0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;

    /// @notice Sentinel head of the Safe modules linked list. The Safe
    /// stores modules as a circular linked list seeded with this sentinel,
    /// so paginated enumeration is started from `address(0x1)`.
    /// @dev Source: `ModuleManager` in
    /// `safe-contracts/contracts/base/ModuleManager.sol` at the v1.4.1 tag.
    address internal constant SAFE_MODULES_SENTINEL = address(0x1);

    /// @notice Assert that the Safe at `safe` is structurally the Safe we
    /// expect: pinned proxy codehash, pinned singleton, pinned version, no
    /// modules, no guard, and pinned fallback handler. Reverts with a typed
    /// error on first failure; returns silently otherwise.
    /// @dev The check ordering is deliberate. Codehash first (cheapest, and
    /// catches an EOA at the address or a fake proxy). Singleton slot next
    /// (catches a swap of the implementation pointer). VERSION() third
    /// (catches an unexpected implementation that happens to have the same
    /// bytecode hash). Modules/guard/fallback handler last, after the proxy
    /// has been proven to be the singleton we expect.
    /// @param safe The Safe to assert invariants on.
    function assertBaseSafeInvariants(IGnosisSafe safe) internal view {
        address safeAddr = address(safe);

        bytes32 actualCodehash;
        assembly ("memory-safe") {
            actualCodehash := extcodehash(safeAddr)
        }
        if (actualCodehash != LibProdSafes.SAFE_V1_4_1_L2_PROXY_CODEHASH) {
            revert SafeProxyCodehashMismatch(safeAddr, LibProdSafes.SAFE_V1_4_1_L2_PROXY_CODEHASH, actualCodehash);
        }

        // Slot 0 of a Safe proxy holds the singleton (master copy) address.
        // Read it raw via `getStorageAt` rather than going through any
        // accessor so a malicious fallback can't shadow the result.
        address actualSingleton = readSafeStorageAddress(safe, 0);
        if (actualSingleton != LibProdSafes.SAFE_V1_4_1_L2_SINGLETON) {
            revert SafeSingletonMismatch(safeAddr, LibProdSafes.SAFE_V1_4_1_L2_SINGLETON, actualSingleton);
        }

        string memory actualVersion = safe.VERSION();
        if (keccak256(bytes(actualVersion)) != keccak256(bytes(LibProdSafes.SAFE_V1_4_1_VERSION))) {
            revert SafeVersionMismatch(safeAddr, LibProdSafes.SAFE_V1_4_1_VERSION, actualVersion);
        }

        // Page size 10 is sufficient: any non-zero module count trips the
        // invariant, and the ST0x production Safe has never had a module
        // enabled. Walking further would only paper over a misconfiguration.
        // The `next` cursor is intentionally discarded — we don't iterate
        // because any non-empty first page already constitutes drift.
        // slither-disable-next-line unused-return
        (address[] memory modules,) = safe.getModulesPaginated(SAFE_MODULES_SENTINEL, 10);
        if (modules.length != 0) {
            revert SafeUnexpectedModules(safeAddr, modules[0]);
        }

        address actualGuard = readSafeStorageAddress(safe, uint256(SAFE_GUARD_STORAGE_SLOT));
        if (actualGuard != address(0)) {
            revert SafeUnexpectedGuard(safeAddr, actualGuard);
        }

        address actualFallbackHandler = readSafeStorageAddress(safe, uint256(SAFE_FALLBACK_HANDLER_STORAGE_SLOT));
        if (actualFallbackHandler != LibProdSafes.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER) {
            revert SafeFallbackHandlerMismatch(
                safeAddr, LibProdSafes.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER, actualFallbackHandler
            );
        }
    }

    /// @notice Reads a single 32-byte storage slot from a Safe via
    /// `getStorageAt(slot, 1)` and interprets the low 20 bytes as an
    /// address. Centralised here so the bytes-to-address decoding is
    /// auditable in one place and reusable across every Safe storage
    /// pin in this library.
    /// @param safe The Safe to query.
    /// @param slot The storage slot index to read.
    /// @return The address stored in the low 20 bytes of `slot`.
    function readSafeStorageAddress(IGnosisSafe safe, uint256 slot) internal view returns (address) {
        bytes memory word = safe.getStorageAt(slot, 1);
        // `getStorageAt(_, 1)` returns exactly 32 bytes; decode through
        // `bytes32` then truncate to `uint160`. Both casts are width-safe
        // by construction and the result is opaque to forge-lint, so the
        // unsafe-typecast warning is suppressed.
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(uint256(bytes32(word))));
    }

    /// @notice Assert that the Safe's owner set matches `expected` in length
    /// and member-by-member. The Safe returns owners in linked-list order;
    /// callers must pass `expected` in the same order or the comparison will
    /// flag a reorder as drift.
    /// @param safe The Safe to query.
    /// @param expected The expected owner addresses in `getOwners()` order.
    function assertOwnerSet(IGnosisSafe safe, address[] memory expected) internal view {
        address[] memory actual = safe.getOwners();
        if (actual.length != expected.length) {
            revert SafeOwnerCountMismatch(address(safe), expected.length, actual.length);
        }
        for (uint256 i = 0; i < expected.length; i++) {
            if (actual[i] != expected[i]) {
                revert SafeOwnerMismatch(address(safe), i, expected[i], actual[i]);
            }
        }
    }

    /// @notice Assert that the Safe's signature threshold matches `expected`.
    /// @param safe The Safe to query.
    /// @param expected The expected threshold.
    function assertThreshold(IGnosisSafe safe, uint256 expected) internal view {
        uint256 actual = safe.getThreshold();
        if (actual != expected) {
            revert SafeThresholdMismatch(address(safe), expected, actual);
        }
    }
}
