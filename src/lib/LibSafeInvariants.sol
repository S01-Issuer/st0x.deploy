// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IGnosisSafe} from "../interface/IGnosisSafe.sol";

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

/// @notice An expected owner is absent from the Safe's `getOwners()` set. Used
/// by the ORDER-INSENSITIVE owner-set check (`assertOwnerSetUnordered`), where
/// only set membership is asserted — the caller supplies the expected roster
/// but not an order, so a missing member is reported by address rather than by
/// index.
/// @param safe The Safe address whose owner set was queried.
/// @param missingOwner The expected owner that was not found in `getOwners()`.
error SafeOwnerSetMismatch(address safe, address missingOwner);

/// @notice No ST0x token-owner Safe address is pinned for the active chain.
/// Deliberately a typed revert rather than a silent fallback to another
/// chain's Safe: authoring or asserting against the wrong chain's Safe is the
/// catastrophic failure this selector exists to prevent.
/// @param chainId The chain id with no pinned token-owner Safe.
error UnsupportedChainForTokenOwnerSafe(uint256 chainId);

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
    // Safe v1.4.1 deployment manifest constants.
    //
    // ST0x runs the SAME Safe policy on every chain but uses whichever
    // canonical v1.4.1 SINGLETON is standard for that chain. Base (an L2) runs
    // the `SafeL2` singleton (extra events for indexers); Ethereum mainnet (L1)
    // runs the `Safe` singleton — the default the Safe UI picks on mainnet.
    // The two are the same audited v1.4.1 contracts differing only in event
    // emission, so `assertImmutableInvariants` accepts EITHER: it reads the
    // proxy's singleton (slot 0), requires it to be one of the two, and pins
    // that variant's proxy + singleton codehash. Owners / threshold / version /
    // modules / guard / fallback are identical across both variants.
    // =========================================================================
    string internal constant SAFE_V1_4_1_VERSION = "1.4.1";
    address internal constant SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER = 0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99;

    // ---- L2 variant (`SafeL2` singleton) — Base's Safe ----
    address internal constant SAFE_V1_4_1_L2_SINGLETON = 0x29fcB43b46531BcA003ddC8FCB67FFE91900C762;
    bytes32 internal constant SAFE_V1_4_1_L2_PROXY_CODEHASH =
        0xb89c1b3bdf2cf8827818646bce9a8f6e372885f8c55e5c07acbd307cb133b000;
    bytes32 internal constant SAFE_V1_4_1_L2_SINGLETON_CODEHASH =
        0xb1f926978a0f44a2c0ec8fe822418ae969bd8c3f18d61e5103100339894f81ff;

    // ---- L1 variant (`Safe` singleton) — Ethereum mainnet's Safe ----
    address internal constant SAFE_V1_4_1_L1_SINGLETON = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    bytes32 internal constant SAFE_V1_4_1_L1_PROXY_CODEHASH =
        0xd7d408ebcd99b2b70be43e20253d6d92a8ea8fab29bd3be7f55b10032331fb4c;
    bytes32 internal constant SAFE_V1_4_1_L1_SINGLETON_CODEHASH =
        0x1fe2df852ba3299d6534ef416eefa406e56ced995bca886ab7a553e6d0c5e1c4;

    // =========================================================================
    // ST0x token-owner Safe current-state pins.
    // =========================================================================

    /// @notice Base mainnet chain id.
    uint256 internal constant BASE_CHAIN_ID = 8453;

    /// @notice Ethereum mainnet chain id.
    uint256 internal constant ETHEREUM_CHAIN_ID = 1;

    /// @notice The ST0x token-owner Safe on **Base** (the reference chain).
    address internal constant STOX_TOKEN_OWNER_SAFE = 0xe70d821f3462a074e63b42d0AaC6523faAe1d611;

    /// @notice The ST0x token-owner Safe on **Ethereum mainnet**.
    ///
    /// A **distinct per-chain address** (the matched-address approach was
    /// abandoned): deployed out-of-band as a v1.4.1 Safe with the SAME owner
    /// set + threshold + policy as Base. The address is a per-chain deploy
    /// artifact, NOT a principal; the whole POLICY (owners, threshold, v1.4.1
    /// identity, fallback handler, no modules/guard) is the shared pin set, and
    /// this Safe is asserted against it — in every way that matters, now and
    /// into the future — by `assertPolicyMatchesBase` (order-insensitive on the
    /// owner set; L1/L2-tolerant on the singleton, since a mainnet Safe runs
    /// the L1 `Safe` singleton while Base runs the L2 `SafeL2`).
    address internal constant STOX_TOKEN_OWNER_SAFE_ETHEREUM = 0x3840aeDaEc8e82f79d8F6a8F6ADCa271E13E0329;

    /// @notice The current expected threshold for `STOX_TOKEN_OWNER_SAFE`:
    /// 3-of-6 against the post-rotation owner roster. Scripts and the
    /// prod-state invariant pin treat this as the canonical current truth
    /// for the Safe's threshold.
    uint256 internal constant STOX_TOKEN_OWNER_SAFE_THRESHOLD = 3;

    /// @notice Owner #1 of `STOX_TOKEN_OWNER_SAFE`. Order matches
    /// `getOwners()` (Safe-internal linked-list order) against the
    /// post-rotation roster: `getOwners()` returns owners newest-first,
    /// so the last signer to be added via `addOwnerWithThreshold` appears
    /// at slot 0.
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_1 = 0x4746095B1Ea1A84446d34448f44e74D3d51f92F2;
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_2 = 0xceC2cb8B8EE4000FFA3F8a7f8E0Fa0A3E3DAb72d;
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_3 = 0x8D5901d8aE48101B59400235ad8614A2e0510466;
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_4 = 0xC1C89b7f5448F447d59f920456A9610f6b2544bC;
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_5 = 0xAB92b327c97A6E7461cBd76E2a789E5e106FF87e;
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_6 = 0x5CCd3cE683b66ff271DDB8915fF528b8fcFa23c2;

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
    /// The check ordering is deliberate. Proxy codehash first (cheapest, a raw
    /// `extcodehash`, and catches an EOA / fake proxy before any call into it) —
    /// accepting either known SafeProxy codehash. Singleton slot next (must be
    /// one of the two canonical v1.4.1 singletons, L1 / L2). Singleton bytecode
    /// third (catches a swap behind the singleton address). VERSION() fourth
    /// (catches an unexpected implementation that happens to have the same
    /// bytecode hash). Modules/guard/fallback handler last, after the proxy has
    /// been proven to be a singleton we expect.
    /// @param safe The Safe to assert immutable invariants on.
    function assertImmutableInvariants(IGnosisSafe safe) internal view {
        address safeAddr = address(safe);

        // Proxy codehash first — a raw `extcodehash`, no call into the proxy —
        // so an EOA / non-Safe is rejected before we trust it enough to read
        // its storage. Accept either known SafeProxy codehash: Base's is a
        // v1.3.0-created proxy (later upgraded to the v1.4.1 L2 singleton),
        // Ethereum's is a v1.4.1-created proxy; both are minimal delegating
        // SafeProxies. The two proxy-origin and L1/L2-singleton dimensions are
        // independent — any known SafeProxy over any known v1.4.1 singleton is
        // a genuine Safe.
        bytes32 actualCodehash;
        assembly ("memory-safe") {
            actualCodehash := extcodehash(safeAddr)
        }
        if (actualCodehash != SAFE_V1_4_1_L2_PROXY_CODEHASH && actualCodehash != SAFE_V1_4_1_L1_PROXY_CODEHASH) {
            revert SafeProxyCodehashMismatch(safeAddr, SAFE_V1_4_1_L2_PROXY_CODEHASH, actualCodehash);
        }

        // Singleton (slot 0) must be one of the two canonical v1.4.1 singletons
        // — L2 `SafeL2` (Base) or L1 `Safe` (Ethereum mainnet). Read raw via
        // `getStorageAt` so a malicious fallback can't shadow the result; the
        // variant selects which singleton codehash to pin.
        address actualSingleton = readSafeStorageAddress(safe, 0);
        bytes32 expectedSingletonCodehash;
        if (actualSingleton == SAFE_V1_4_1_L2_SINGLETON) {
            expectedSingletonCodehash = SAFE_V1_4_1_L2_SINGLETON_CODEHASH;
        } else if (actualSingleton == SAFE_V1_4_1_L1_SINGLETON) {
            expectedSingletonCodehash = SAFE_V1_4_1_L1_SINGLETON_CODEHASH;
        } else {
            revert SafeSingletonMismatch(safeAddr, SAFE_V1_4_1_L2_SINGLETON, actualSingleton);
        }

        // Singleton bytecode for the selected variant. Address pin alone trusts
        // whatever code lives at the singleton; pinning its codehash too means a
        // swap there (preserving the pointer + superficial view returns) cannot
        // route every implementation-backed call through attacker code.
        // Asserted before `VERSION()` and any other read that delegate-routes
        // through the singleton.
        bytes32 actualSingletonCodehash;
        assembly ("memory-safe") {
            actualSingletonCodehash := extcodehash(actualSingleton)
        }
        if (actualSingletonCodehash != expectedSingletonCodehash) {
            revert SafeSingletonBytecodeMismatch(
                safeAddr, actualSingleton, expectedSingletonCodehash, actualSingletonCodehash
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

    /// @notice Expected owner set for `STOX_TOKEN_OWNER_SAFE` in
    /// `getOwners()` order. Helper because Solidity 0.8 cannot express a
    /// file-scope `constant address[]`.
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

    /// @notice The ST0x token-owner Safe address for the active chain, selected
    /// by chain id. The Safe address is a per-chain deploy artifact (the
    /// matched-address approach was abandoned), so consumers that must resolve
    /// "this chain's Safe" — the multichain production-state bundle, the
    /// cross-chain parity pin, the Ethereum token-authorise script — read it
    /// here. Reverts `UnsupportedChainForTokenOwnerSafe` for any chain without
    /// a pinned Safe rather than falling back to another chain's address.
    /// @param chainId The active chain id (`block.chainid`).
    /// @return safe The chain's token-owner Safe (`address(0)` on Ethereum
    /// until the deployed Safe is pinned).
    function safeForChainId(uint256 chainId) internal pure returns (address safe) {
        if (chainId == BASE_CHAIN_ID) {
            return STOX_TOKEN_OWNER_SAFE;
        }
        if (chainId == ETHEREUM_CHAIN_ID) {
            return STOX_TOKEN_OWNER_SAFE_ETHEREUM;
        }
        revert UnsupportedChainForTokenOwnerSafe(chainId);
    }

    /// @notice Assert the Safe's owner set equals `expected` as a SET — same
    /// length and same members — WITHOUT requiring the same `getOwners()`
    /// order. Unlike `assertOwnerSet` (order-sensitive, for Base's pinned
    /// roster), this is the right check across chains: `getOwners()` returns
    /// owners in Safe-internal linked-list order, which is an incidental
    /// artifact of the order owners were added at setup / rotation and differs
    /// between two Safes that carry the identical roster. Owner order is not a
    /// policy property, so cross-chain parity asserts membership, not order.
    /// @dev Safe forbids duplicate owners, so with equal lengths "every
    /// expected owner is present" implies "no unexpected owners" — a one-way
    /// membership scan is sufficient.
    /// @param safe The Safe to query.
    /// @param expected The expected owner addresses, in any order.
    function assertOwnerSetUnordered(IGnosisSafe safe, address[] memory expected) internal view {
        address[] memory actual = safe.getOwners();
        if (actual.length != expected.length) {
            revert SafeOwnerCountMismatch(address(safe), expected.length, actual.length);
        }
        for (uint256 i = 0; i < expected.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < actual.length; j++) {
                if (actual[j] == expected[i]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                revert SafeOwnerSetMismatch(address(safe), expected[i]);
            }
        }
    }

    /// @notice Assert a chain's Safe carries the SAME policy as Base — in every
    /// way that matters: the v1.4.1 immutable identity (proxy codehash,
    /// singleton pointer + bytecode, version, no modules, no guard, pinned
    /// fallback handler), the same owner SET, and the same threshold — as
    /// pinned in this library (which is Base's current truth). The owner check
    /// is order-INSENSITIVE (`assertOwnerSetUnordered`), because the only thing
    /// that legitimately differs across chains is the Safe ADDRESS (and, as a
    /// consequence of a fresh deploy, the incidental `getOwners()` order).
    /// @dev This is the cross-chain / non-baseline-chain bundle. Base's own
    /// pin test uses the order-SENSITIVE `assertAll` against its pinned roster.
    /// Because the pins are the single source of truth for the policy and Base
    /// is asserted against them too, asserting a chain's Safe here transitively
    /// proves it matches Base — now, and on every scheduled CI run into the
    /// future (if Base's policy changes, the pins move and this goes red until
    /// the chain's Safe is realigned).
    /// @param safe The chain's Safe to validate against Base's shared policy.
    function assertPolicyMatchesBase(IGnosisSafe safe) internal view {
        assertImmutableInvariants(safe);
        assertOwnerSetUnordered(safe, expectedOwners());
        assertThreshold(safe, STOX_TOKEN_OWNER_SAFE_THRESHOLD);
    }

    /// @notice Resolve the active chain's token-owner Safe AND assert it is in
    /// its expected state, choosing the chain-appropriate assertion. This is
    /// the single entry point a broadcast script's pre-flight and the scheduled
    /// CI pin both call, so the assertion that gates a manual broadcast is the
    /// identical one CI runs every commit — a broadcast can never revert on a
    /// Safe check CI has not already exercised on that chain.
    ///
    /// The reference chain (Base) is pinned EXACTLY: the order-sensitive
    /// `assertAll` against the canonical `expectedOwners()` roster + pinned
    /// threshold. Every other chain is asserted for the SAME POLICY as Base via
    /// the order-insensitive `assertPolicyMatchesBase` — a fresh per-chain Safe
    /// carries the identical owner SET + threshold + v1.4.1 identity, but its
    /// `getOwners()` linked-list order is an incidental deploy artifact, so
    /// order is not asserted off-baseline.
    ///
    /// Reverts `UnsupportedChainForTokenOwnerSafe` (via `safeForChainId`) for a
    /// chain without a pinned Safe rather than silently asserting the wrong
    /// chain's Safe.
    /// @param chainId The active chain id (`block.chainid`).
    /// @return safe The chain's token-owner Safe, proven in-policy.
    function assertActiveChainTokenOwnerSafe(uint256 chainId) internal view returns (address safe) {
        safe = safeForChainId(chainId);
        if (chainId == BASE_CHAIN_ID) {
            assertAll(IGnosisSafe(safe));
        } else {
            assertPolicyMatchesBase(IGnosisSafe(safe));
        }
    }
}
