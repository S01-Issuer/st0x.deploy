// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IGnosisSafe} from "../interface/IGnosisSafe.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {IOwnable} from "./LibTokenInvariants.sol";

/// @notice The runtime codehash at the Safe's address does not match the
/// pinned Safe v1.4.1 L2 proxy codehash. Signals either that the address has
/// been swapped under us or that the Safe singleton has been redeployed with
/// different bytecode.
/// @param safe The Safe address whose codehash was checked.
/// @param expected The pinned codehash that was expected
/// (`SAFE_V1_4_1_L2_PROXY_CODEHASH`).
/// @param actual The codehash returned by `extcodehash(safe)`.
error SafeProxyCodehashMismatch(address safe, bytes32 expected, bytes32 actual);

/// @notice The implementation pointer stored at Safe storage slot `0x0` does
/// not match the pinned Safe v1.4.1 L2 singleton address. Used to detect a
/// `setImplementation`-style takeover that would route every call through a
/// different singleton.
/// @param safe The Safe proxy address that was inspected.
/// @param expected The pinned singleton address
/// (`SAFE_V1_4_1_L2_SINGLETON`).
/// @param actual The singleton address read from slot `0x0` of the proxy.
error SafeSingletonMismatch(address safe, address expected, address actual);

/// @notice The Safe singleton's runtime bytecode codehash does not match the
/// pinned `SAFE_V1_4_1_L2_SINGLETON_CODEHASH`. Pinning the
/// singleton address alone trusts the bytecode at that address; a swap (e.g.
/// `SELFDESTRUCT` + recreate, or a delegatecall-time substitution on a
/// forked test environment) could preserve the address while replacing the
/// implementation entirely. Asserting the singleton codehash closes that
/// gap before any implementation-backed read (`VERSION()`, `getOwners()`,
/// `getThreshold()`, etc.) is trusted.
/// @param safe The Safe proxy address that was inspected.
/// @param singleton The singleton address read from slot `0x0` of the proxy.
/// @param expected The pinned singleton codehash
/// (`SAFE_V1_4_1_L2_SINGLETON_CODEHASH`).
/// @param actual The codehash observed at `singleton`.
error SafeSingletonBytecodeMismatch(address safe, address singleton, bytes32 expected, bytes32 actual);

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
/// (`SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER`).
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

/// @notice The address supplied as a beacon has no runtime code. Either the
/// beacon was never deployed at this address or it has been
/// `SELFDESTRUCT`-ed. Caught first so later reads against the address are
/// only attempted once it is known to be a contract.
/// @param beacon The address that was expected to be a deployed beacon.
error BeaconNotDeployed(address beacon);

/// @notice The beacon's runtime codehash does not match the pinned OZ
/// `UpgradeableBeacon` bytecode (`UPGRADEABLE_BEACON_CODEHASH`).
/// Signals either an address swap or a look-alike contract shadowing the
/// `implementation()` / `owner()` selectors. The codehash pin is what lets
/// the access-control behaviour be trusted as OZ's audited bytecode rather
/// than re-tested here.
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

/// @title LibSafeInvariants
/// @notice Reusable invariant assertions for a Safe v1.4.1 L2 multisig
/// pinned to the ST0x token-owner deployment. Each public assertion either
/// returns silently when the invariant holds against the live chain state
/// or reverts with a typed error that pinpoints the drift.
/// @dev The library splits checks into two categories:
///
/// - **Immutable invariants** (`assertImmutableInvariants`) — pure Safe
///   identity and configuration properties that always hold against this
///   Safe regardless of any pending or past migration: proxy codehash,
///   singleton pointer + bytecode, version, modules empty, guard zero, and
///   fallback handler pinned. The same set is evaluated pre-migration and
///   post-migration; nothing here is parameterised on operational intent.
///
/// - **Parameterised state assertions** (`assertOwnerSet`, `assertThreshold`)
///   — properties whose expected value is supplied by the caller because
///   the caller is deliberately mutating that property (notably the
///   threshold migration). Wrong values here are caller intent, not Safe
///   drift, so the comparison target is an argument.
///
/// The `assertAll` overloads bundle the Safe-side immutable invariants
/// and the two parameterised checks into a single call site. The pattern
/// mirrors `StoxProdV2Test::checkAllV2OnChain`: a full-args helper that
/// takes every expected value, and a no-arg default that fills in the
/// current-truth pins from `LibSafeInvariants`. Token-side invariants are
/// composed alongside these by `LibInvariants.assertAll` for callers
/// asserting the full production state; this lib is Safe-only by design
/// so the file name doesn't mislead.
///
/// Centralising the assertions here keeps drift detection consistent
/// across the threshold migration script, its tests, the post-migration
/// pin, and any future migrations: anyone extending the Safe touch-points
/// only needs to add new invariants in one place.
///
/// All storage-slot constants come from the Safe v1.4.1 source:
/// https://github.com/safe-global/safe-contracts/tree/v1.4.1/contracts
/// Singleton (master copy) lives at slot `0x0` of the proxy by virtue of
/// `SafeProxy`'s minimal storage layout; the guard slot and fallback handler
/// slot are explicit constants in `GuardManager`/`FallbackManager` chosen so
/// they cannot collide with the owner/module/threshold linked-list slots.
library LibSafeInvariants {
    // =========================================================================
    // Safe v1.4.1 deployment manifest constants. Universal to every v1.4.1 L2
    // Safe; sourced from `safe-deployments` for chainId 8453 and cross-checked
    // against the live ST0x production Safe.
    // =========================================================================

    /// @notice Safe v1.4.1 L2 singleton (master copy) address on Base.
    /// Verified by reading proxy storage slot `0x0` of
    /// `STOX_TOKEN_OWNER_SAFE` and matching against the
    /// `safe-deployments` manifest.
    address internal constant SAFE_V1_4_1_L2_SINGLETON = 0x29fcB43b46531BcA003ddC8FCB67FFE91900C762;

    /// @notice Runtime codehash of a Safe v1.4.1 proxy on Base. Equal to
    /// `extcodehash(STOX_TOKEN_OWNER_SAFE)` and to every other v1.4.1 L2
    /// proxy pointing at `SAFE_V1_4_1_L2_SINGLETON`. Pinning this codehash
    /// guards against the Safe address being replaced by an EOA-controlled
    /// contract or a fake proxy pointing at a malicious singleton.
    bytes32 internal constant SAFE_V1_4_1_L2_PROXY_CODEHASH =
        0xb89c1b3bdf2cf8827818646bce9a8f6e372885f8c55e5c07acbd307cb133b000;

    /// @notice Expected `VERSION()` string from a Safe v1.4.1 singleton.
    string internal constant SAFE_V1_4_1_VERSION = "1.4.1";

    /// @notice Runtime codehash of the Safe v1.4.1 L2 singleton bytecode at
    /// `SAFE_V1_4_1_L2_SINGLETON`. Pinning this guards against an attacker
    /// who replaces the bytecode at the singleton address (e.g. via
    /// `SELFDESTRUCT` + re-create) while preserving the proxy codehash.
    /// Without this pin, every implementation-backed accessor on the Safe
    /// (`VERSION()`, `getOwners()`, `getThreshold()`, etc.) is mediated by
    /// untrusted code at the singleton address. Asserting this codehash
    /// before any of those reads closes that gap.
    /// @dev Computed via `keccak256(eth_getCode(SAFE_V1_4_1_L2_SINGLETON))`
    /// on Base on 2026-05-20.
    bytes32 internal constant SAFE_V1_4_1_L2_SINGLETON_CODEHASH =
        0xb1f926978a0f44a2c0ec8fe822418ae969bd8c3f18d61e5103100339894f81ff;

    /// @notice CompatibilityFallbackHandler v1.4.1 address on Base. Verified
    /// against the live Safe's fallback handler storage slot. Pinned so a
    /// swapped-in malicious handler that shadows view selectors via
    /// fallback can be detected by `assertImmutableInvariants`.
    /// @dev Source: github.com/safe-global/safe-deployments
    /// `src/assets/v1.4.1/compatibility_fallback_handler.json` (chainId
    /// 8453 entry). Cross-checked on Base on 2026-05-20.
    address internal constant SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER = 0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99;

    // =========================================================================
    // ST0x token-owner Safe pins. Current-state invariants for the specific
    // Safe at `STOX_TOKEN_OWNER_SAFE`; updated when the live state changes
    // (e.g. the threshold migration bumps `STOX_TOKEN_OWNER_SAFE_THRESHOLD`
    // from `1` to `3` in the same PR that records the post-execution state).
    // =========================================================================

    /// @notice The Safe that owns every ST0x receipt vault on Base. Subject
    /// of the threshold migration (1 -> 3, against the post-rotation
    /// 6-owner roster).
    /// https://basescan.org/address/0xe70d821f3462A074E63b42D0aac6523faAe1D611
    address internal constant STOX_TOKEN_OWNER_SAFE = 0xe70d821f3462a074e63b42d0AaC6523faAe1d611;

    /// @notice The current expected threshold for `STOX_TOKEN_OWNER_SAFE`.
    /// Updated by the threshold-migration PR family once live execution
    /// lands: scripts and the post-migration pin both treat this constant
    /// as the canonical current truth, so the value bumps from `1` to `3`
    /// in the same PR that records the live post-execution state.
    uint256 internal constant STOX_TOKEN_OWNER_SAFE_THRESHOLD = 1;

    /// @notice Owner #1 of `STOX_TOKEN_OWNER_SAFE`. Order matches
    /// `getOwners()` (Safe-internal linked-list order) against the
    /// post-rotation roster: `getOwners()` returns owners newest-first,
    /// so the last signer to be added via `addOwnerWithThreshold` appears
    /// at slot 0.
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_1 = 0x4746095B1Ea1A84446d34448f44e74D3d51f92F2;

    /// @notice Owner #2 of `STOX_TOKEN_OWNER_SAFE`.
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_2 = 0xceC2cb8B8EE4000FFA3F8a7f8E0Fa0A3E3DAb72d;

    /// @notice Owner #3 of `STOX_TOKEN_OWNER_SAFE`.
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_3 = 0x8D5901d8aE48101B59400235ad8614A2e0510466;

    /// @notice Owner #4 of `STOX_TOKEN_OWNER_SAFE`.
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_4 = 0xC1C89b7f5448F447d59f920456A9610f6b2544bC;

    /// @notice Owner #5 of `STOX_TOKEN_OWNER_SAFE`.
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_5 = 0xAB92b327c97A6E7461cBd76E2a789E5e106FF87e;

    /// @notice Owner #6 of `STOX_TOKEN_OWNER_SAFE`.
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_6 = 0x5CCd3cE683b66ff271DDB8915fF528b8fcFa23c2;

    // =========================================================================
    // Storage layout constants for paginated / direct slot reads.
    // =========================================================================

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

    /// @notice Assert every immutable invariant of the Safe at `safe`:
    /// pinned proxy codehash, pinned singleton pointer, pinned singleton
    /// bytecode, pinned version, no modules, no guard, and pinned fallback
    /// handler. Reverts with a typed error on first failure; returns
    /// silently otherwise.
    /// @dev "Immutable" here means pure Safe identity and configuration
    /// properties that should hold against the production Safe at any
    /// point in time, regardless of pending or past operational
    /// migrations. The same set is asserted pre-migration and
    /// post-migration; nothing in this call is parameterised on caller
    /// intent. Token-side uniformity (vault owner/authoriser) is a
    /// separate concern composed into `assertAll` via `LibTokenInvariants`
    /// rather than here, because it is a property of the token deployment
    /// rather than of the Safe.
    ///
    /// The check ordering is deliberate. Codehash first (cheapest, and
    /// catches an EOA at the address or a fake proxy). Singleton slot next
    /// (catches a swap of the implementation pointer). Singleton bytecode
    /// third (catches a swap behind the singleton address). VERSION()
    /// fourth (catches an unexpected implementation that happens to have
    /// the same bytecode hash). Modules/guard/fallback handler last, after
    /// the proxy has been proven to be the singleton we expect.
    /// @param safe The Safe to assert immutable invariants on.
    function assertImmutableInvariants(IGnosisSafe safe) internal view {
        address safeAddr = address(safe);

        bytes32 actualCodehash;
        assembly ("memory-safe") {
            actualCodehash := extcodehash(safeAddr)
        }
        if (actualCodehash != SAFE_V1_4_1_L2_PROXY_CODEHASH) {
            revert SafeProxyCodehashMismatch(safeAddr, SAFE_V1_4_1_L2_PROXY_CODEHASH, actualCodehash);
        }

        // Slot 0 of a Safe proxy holds the singleton (master copy) address.
        // Read it raw via `getStorageAt` rather than going through any
        // accessor so a malicious fallback can't shadow the result.
        address actualSingleton = readSafeStorageAddress(safe, 0);
        if (actualSingleton != SAFE_V1_4_1_L2_SINGLETON) {
            revert SafeSingletonMismatch(safeAddr, SAFE_V1_4_1_L2_SINGLETON, actualSingleton);
        }

        // Address pin alone trusts whatever code lives at the singleton
        // address. Pin the singleton's bytecode too so a swap there
        // (preserving the proxy codehash and superficial view returns)
        // cannot route every implementation-backed call through attacker
        // code. Asserted before `VERSION()` and any other read that
        // delegate-routes through the singleton.
        bytes32 actualSingletonCodehash;
        assembly ("memory-safe") {
            actualSingletonCodehash := extcodehash(actualSingleton)
        }
        if (actualSingletonCodehash != SAFE_V1_4_1_L2_SINGLETON_CODEHASH) {
            revert SafeSingletonBytecodeMismatch(
                safeAddr, actualSingleton, SAFE_V1_4_1_L2_SINGLETON_CODEHASH, actualSingletonCodehash
            );
        }

        string memory actualVersion = safe.VERSION();
        if (keccak256(bytes(actualVersion)) != keccak256(bytes(SAFE_V1_4_1_VERSION))) {
            revert SafeVersionMismatch(safeAddr, SAFE_V1_4_1_VERSION, actualVersion);
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
        if (actualFallbackHandler != SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER) {
            revert SafeFallbackHandlerMismatch(
                safeAddr, SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER, actualFallbackHandler
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

    /// @notice Full-args Safe-side invariant bundle. Use when you want to
    /// override the expected threshold or owner set from the `LibSafeInvariants`
    /// current-truth pins — typically only when running a script that
    /// intentionally changes one of those (post-state assertion).
    /// @dev Composes the Safe-side invariants only: immutable Safe
    /// identity/config, owner set, and threshold. Token-side uniformity
    /// invariants are composed in `LibInvariants.assertAll` so the
    /// full-production-state bundle still exists, but they don't live
    /// here — this lib is purely Safe-side.
    ///
    /// Mirrors the `StoxProdV2Test::checkAllV2OnChain` pattern: a
    /// full-args helper alongside a no-arg overload. Migration scripts
    /// call the no-arg overload pre-execution to assert the pinned
    /// current truth, then call this overload post-execution with the
    /// deliberately-changed expectation.
    /// @param safe The Safe to validate.
    /// @param expectedThreshold The expected signature threshold.
    /// @param expectedOwnerSet The expected owner set in `getOwners()` order.
    function assertAll(IGnosisSafe safe, uint256 expectedThreshold, address[] memory expectedOwnerSet) internal view {
        assertImmutableInvariants(safe);
        assertOwnerSet(safe, expectedOwnerSet);
        assertThreshold(safe, expectedThreshold);
    }

    /// @notice No-arg Safe-side invariant bundle that fills in the
    /// `LibSafeInvariants`-pinned current-truth defaults: the threshold from
    /// `STOX_TOKEN_OWNER_SAFE_THRESHOLD` and the owner set from
    /// `expectedOwners()`. Pre-flight at the start of every script and
    /// fork test that runs against the production Safe; if this passes
    /// silently, the Safe is in its current expected state.
    /// @dev The full-args overload is the right call site only when a
    /// caller is *deliberately* asserting a state that diverges from the
    /// pinned current truth (e.g. the migration script's post-state
    /// re-check after it has simulated `changeThreshold`).
    /// @param safe The Safe to validate against the pinned current truth.
    function assertAll(IGnosisSafe safe) internal view {
        assertAll(safe, STOX_TOKEN_OWNER_SAFE_THRESHOLD, expectedOwners());
    }

    /// @notice Returns the expected owner set for `STOX_TOKEN_OWNER_SAFE` in
    /// the exact order returned by `getOwners()` against an unpinned Base
    /// head fork (the live-state pin lives in
    /// `StoxProdV2.t.sol::testProdDeployBaseV2`, which selects head rather
    /// than pinning to a historical block so the next CI run catches any
    /// further drift). Provided as a helper because Solidity 0.8 cannot
    /// express a file-scope `constant address[]` and declaring the array
    /// as `immutable` is contract-scoped only.
    /// @return The six owners of the ST0x token-owner Safe in
    /// `getOwners()` order.
    function expectedOwners() internal pure returns (address[] memory) {
        address[] memory owners = new address[](6);
        owners[0] = STOX_TOKEN_OWNER_SAFE_OWNER_1;
        owners[1] = STOX_TOKEN_OWNER_SAFE_OWNER_2;
        owners[2] = STOX_TOKEN_OWNER_SAFE_OWNER_3;
        owners[3] = STOX_TOKEN_OWNER_SAFE_OWNER_4;
        owners[4] = STOX_TOKEN_OWNER_SAFE_OWNER_5;
        owners[5] = STOX_TOKEN_OWNER_SAFE_OWNER_6;
        return owners;
    }

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
    /// Check ordering mirrors `assertImmutableInvariants`: code presence
    /// first (cheapest, and catches an EOA or empty address), codehash
    /// second (catches a look-alike), then the storage-backed reads
    /// (`owner()`, `implementation()`) once the bytecode is proven to be the
    /// OZ beacon, and the implementation code-presence check last because it
    /// depends on the implementation read having succeeded.
    /// @notice OpenZeppelin `UpgradeableBeacon` runtime codehash. Pinned
    /// here so the beacon-side codehash check has a concrete invariant
    /// target; matches the bytecode at every prod beacon deployment.
    bytes32 internal constant UPGRADEABLE_BEACON_CODEHASH =
        0x8e95867e52db417944afd90f3b6c3c980962831e8a944e7f6958ba8f8cc10630;

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
