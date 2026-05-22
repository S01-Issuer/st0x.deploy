// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibProdSafes
/// @notice Production Safe constants for the ST0x token-owner multisig on
/// Base. Pinned addresses, codehashes, slot values, and the expected owner
/// set (currently 4 owners) are derived from live on-chain state and the
/// canonical Safe deployment manifest, then re-asserted from fork tests so
/// that drift between this file and reality trips CI rather than slipping
/// into a migration script.
/// @dev Scope: the multisig threshold migration raises this Safe from
/// 1-of-4 to 3-of-4. (Originally specced as 1-of-5 -> 3-of-5; the owner
/// roster was reduced to four on 2026-05-18 via the `RemovedOwner` event
/// at block 46156528, before the threshold migration was executed.)
/// @dev Sources:
/// - Safe v1.4.1 L2 singleton & proxy: github.com/safe-global/safe-deployments
///   under `src/assets/v1.4.1/safe_l2.json` (chainId 8453 entry). Both the
///   singleton address and the proxy bytecode are deterministic across the
///   Safe L2 deployment, so the proxy codehash below is also constant.
/// - ST0x Safe address & live state read on Base on 2026-05-20 via
///   `cast call`. The owner set, threshold, and storage-slot pins below
///   match the post-removal state. `StoxProdV2.t.sol::testProdDeployBaseV2`
///   exercises these against an unpinned head fork (via
///   `LibSafeInvariants.assertAll`) so the next CI run catches any further
///   drift; see that test for why `LibTestProd.PROD_TEST_BLOCK_NUMBER_BASE`
///   is not reused.
library LibProdSafes {
    /// @notice Safe v1.4.1 L2 singleton (master copy) address on Base.
    /// Verified by reading proxy storage slot `0x0` of
    /// `STOX_TOKEN_OWNER_SAFE` and matching against the
    /// `safe-deployments` manifest.
    address constant SAFE_V1_4_1_L2_SINGLETON = 0x29fcB43b46531BcA003ddC8FCB67FFE91900C762;

    /// @notice Runtime codehash of a Safe v1.4.1 proxy on Base. Equal to
    /// `extcodehash(STOX_TOKEN_OWNER_SAFE)` and to every other v1.4.1 L2
    /// proxy pointing at `SAFE_V1_4_1_L2_SINGLETON`. Pinning this codehash
    /// guards against the Safe address being replaced by an EOA-controlled
    /// contract or a fake proxy pointing at a malicious singleton.
    bytes32 constant SAFE_V1_4_1_L2_PROXY_CODEHASH = 0xb89c1b3bdf2cf8827818646bce9a8f6e372885f8c55e5c07acbd307cb133b000;

    /// @notice Expected `VERSION()` string from a Safe v1.4.1 singleton.
    string constant SAFE_V1_4_1_VERSION = "1.4.1";

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
    bytes32 constant SAFE_V1_4_1_L2_SINGLETON_CODEHASH =
        0xb1f926978a0f44a2c0ec8fe822418ae969bd8c3f18d61e5103100339894f81ff;

    /// @notice CompatibilityFallbackHandler v1.4.1 address on Base. Verified
    /// against the live Safe's fallback handler storage slot. Pinned so a
    /// swapped-in malicious handler that shadows view selectors via
    /// fallback can be detected by `LibSafeInvariants.assertImmutableInvariants`.
    /// @dev Source: github.com/safe-global/safe-deployments
    /// `src/assets/v1.4.1/compatibility_fallback_handler.json` (chainId
    /// 8453 entry). Cross-checked on Base on 2026-05-20.
    address constant SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER = 0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99;

    /// @notice The Safe that owns every ST0x receipt vault on Base. Subject
    /// of the threshold migration (1 -> 3, against the current 4-owner
    /// roster).
    /// https://basescan.org/address/0xe70d821f3462A074E63b42D0aac6523faAe1D611
    address constant STOX_TOKEN_OWNER_SAFE = 0xe70d821f3462a074e63b42d0AaC6523faAe1d611;

    /// @notice The current expected threshold for `STOX_TOKEN_OWNER_SAFE`.
    /// Updated by the threshold-migration PR family once live execution
    /// lands: scripts and the post-migration pin both treat this constant
    /// as the canonical current truth, so the value bumps from `1` to `3`
    /// in the same PR that records the live post-execution state.
    uint256 constant STOX_TOKEN_OWNER_SAFE_THRESHOLD = 1;

    /// @notice Owner #1 of `STOX_TOKEN_OWNER_SAFE`. Order matches
    /// `getOwners()` (Safe-internal linked-list order).
    address constant STOX_TOKEN_OWNER_SAFE_OWNER_1 = 0x19f95a84aa1C48A2c6a7B2d5de164331c86D030C;

    /// @notice Owner #2 of `STOX_TOKEN_OWNER_SAFE`. Order matches
    /// `getOwners()` (Safe-internal linked-list order).
    address constant STOX_TOKEN_OWNER_SAFE_OWNER_2 = 0x8f6bF4A948Af2Fc74eE34982C4435a7C013D1A52;

    /// @notice Owner #3 of `STOX_TOKEN_OWNER_SAFE`. Order matches
    /// `getOwners()` (Safe-internal linked-list order). This slot previously
    /// held the now-removed owner `0x691AcCd4...`; after the 2026-05-18
    /// `RemovedOwner` event at block 46156528 the linked list shifted up
    /// and what was owner #4 became owner #3.
    address constant STOX_TOKEN_OWNER_SAFE_OWNER_3 = 0x91E2AF6Ee6bc5d0f7AA1644Bb94957932629d2DB;

    /// @notice Owner #4 of `STOX_TOKEN_OWNER_SAFE`. Order matches
    /// `getOwners()` (Safe-internal linked-list order). Formerly owner #5
    /// before the 2026-05-18 roster reduction.
    address constant STOX_TOKEN_OWNER_SAFE_OWNER_4 = 0xBF8a5DE7BaAFaD46495217d467F43ae305cb900f;

    /// @notice Returns the expected owner set for `STOX_TOKEN_OWNER_SAFE` in
    /// the exact order returned by `getOwners()` against an unpinned Base
    /// head fork (the live-state pin lives in
    /// `StoxProdV2.t.sol::testProdDeployBaseV2`, which selects head rather
    /// than pinning to a historical block so the next CI run catches any
    /// further drift). Provided as a helper because Solidity 0.8 cannot
    /// express a file-scope `constant address[]` and declaring the array
    /// as `immutable` is contract-scoped only.
    /// @return The four owners of the ST0x token-owner Safe in
    /// `getOwners()` order.
    function expectedOwners() internal pure returns (address[] memory) {
        address[] memory owners = new address[](4);
        owners[0] = STOX_TOKEN_OWNER_SAFE_OWNER_1;
        owners[1] = STOX_TOKEN_OWNER_SAFE_OWNER_2;
        owners[2] = STOX_TOKEN_OWNER_SAFE_OWNER_3;
        owners[3] = STOX_TOKEN_OWNER_SAFE_OWNER_4;
        return owners;
    }
}
