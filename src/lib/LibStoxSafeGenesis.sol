// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibStoxSafeGenesis
/// @notice The genesis creation parameters of the ST0x token-owner Safe,
/// recovered from its Base creation transaction (Safe transaction service,
/// 2026-07-07). A Gnosis Safe address is `CREATE2(proxyFactory, salt,
/// keccak256(proxyCreationCode ++ singleton))` where
/// `salt = keccak256(keccak256(initializer) ++ saltNonce)`. So replaying the
/// EXACT genesis factory + singleton + initializer + salt on another chain
/// reproduces the SAME address — which is what lets Ethereum carry the same
/// token-owner Safe address as Base (RAI-1109, Josh 2026-07-07).
///
/// @dev Two things the address depends on that are easy to get wrong:
///
/// 1. **Version.** The Base Safe was CREATED as a Safe **v1.3.0** (factory
///    `0xa6B71E26…`, singleton `0x3E5c6364…`), then later upgraded to v1.4.1
///    (`LibSafeInvariants` pins the current v1.4.1 state). The address is
///    fixed by the v1.3.0 creation params, so the reproduction MUST use the
///    v1.3.0 factory + singleton, not the current v1.4.1 ones.
///
/// 2. **Genesis ≠ current state.** Genesis was 3 owners / threshold 2; the
///    live Base Safe is now 6 owners / threshold 3 on v1.4.1. Reproducing the
///    address gives a Safe in the GENESIS state; reaching parity with Base's
///    current policy is a separate post-deploy replay (upgrade to 1.4.1, add
///    the 3 later owners, raise threshold to 3), signed by the genesis
///    owners. See `docs/ETHEREUM_BOOTSTRAP.md` § 3a.
///
/// The canonical v1.3.0 factory, singleton and fallback handler are deployed
/// at these same addresses on Ethereum mainnet (verified 2026-07-07), so the
/// reproduction is feasible without deploying any Safe infrastructure first.
library LibStoxSafeGenesis {
    /// @notice Canonical Safe v1.3.0 `GnosisSafeProxyFactory`. Same address
    /// on Base and Ethereum.
    address internal constant SAFE_1_3_0_PROXY_FACTORY = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;

    /// @notice Canonical Safe v1.3.0 `GnosisSafeL2` singleton (mastercopy)
    /// the Base Safe was created against.
    address internal constant SAFE_1_3_0_L2_SINGLETON = 0x3E5c63644E683549055b9Be8653de26E0B4CD36E;

    /// @notice The v1.3.0 `CompatibilityFallbackHandler` set in the genesis
    /// initializer. Pinned for auditability of the setup calldata below.
    address internal constant SAFE_1_3_0_FALLBACK_HANDLER = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;

    /// @notice The genesis `saltNonce` passed to `createProxyWithNonce`.
    uint256 internal constant GENESIS_SALT_NONCE = 0;

    /// @notice Genesis owner #1 (of 3). https://basescan.org/address/0x691AcCd4C6Dc147e3Cf983bcbf3198896E794451
    address internal constant GENESIS_OWNER_1 = 0x691AcCd4C6Dc147e3Cf983bcbf3198896E794451;
    /// @notice Genesis owner #2 (of 3). https://basescan.org/address/0x91E2AF6Ee6bc5d0f7AA1644Bb94957932629d2DB
    address internal constant GENESIS_OWNER_2 = 0x91E2AF6Ee6bc5d0f7AA1644Bb94957932629d2DB;
    /// @notice Genesis owner #3 (of 3). https://basescan.org/address/0xBF8a5DE7BaAFaD46495217d467F43ae305cb900f
    address internal constant GENESIS_OWNER_3 = 0xBF8a5DE7BaAFaD46495217d467F43ae305cb900f;

    /// @notice The genesis signature threshold.
    uint256 internal constant GENESIS_THRESHOLD = 2;

    /// @notice The exact `initializer` (a `setup(...)` call) the Base Safe was
    /// created with, verbatim from the creation transaction. `keccak256` of
    /// this — combined with `GENESIS_SALT_NONCE` — is the CREATE2 salt, so a
    /// single byte changed here would change the reproduced address. Decodes
    /// to: owners [GENESIS_OWNER_1..3], threshold 2, to `address(0)`, data
    /// empty, fallbackHandler `SAFE_1_3_0_FALLBACK_HANDLER`, paymentToken
    /// `address(0)`, payment 0, paymentReceiver `0x5afe7a11…`.
    bytes internal constant GENESIS_SETUP =
        hex"b63e800d0000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000180000000000000000000000000f48f2b2d2a534e402487b3ee7c18c33aec0fe5e4000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005afe7a11e70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000691accd4c6dc147e3cf983bcbf3198896e79445100000000000000000000000091e2af6ee6bc5d0f7aa1644bb94957932629d2db000000000000000000000000bf8a5de7baafad46495217d467f43ae305cb900f0000000000000000000000000000000000000000000000000000000000000000";
}
