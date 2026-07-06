// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "./LibStoxDeployNetworks.sol";

/// @notice The operational principals that hold roles on a chain's ST0x
/// deployment. The role-grant STRUCTURE (which role kinds each principal
/// kind holds — see `LibAuthoriserInvariants.expectedGrants`) is identical
/// on every chain; the ADDRESSES filling those slots are per-chain in the
/// general case, but for ST0x they are deliberately kept identical across
/// chains: the token-owner Safe is reproduced at its Base address on every
/// chain (a Safe proxy address is CREATE2-deterministic in its factory +
/// singleton + genesis initializer + salt, so replaying the genesis
/// creation reproduces the same address — see `LibStoxSafeGenesis` /
/// `docs/ETHEREUM_BOOTSTRAP.md` § 3a), and the issuance service signer is
/// shared. The struct stays per-chain so a future chain CAN diverge, but
/// today Base and Ethereum resolve to the same two addresses.
/// @param network The rain-deploy / foundry.toml network name this principal
/// set belongs to, so a principals value is self-describing when passed
/// through scripts and tests.
/// @param tokenOwnerSafe The chain's ST0x token-owner Safe: owner of every
/// production receipt vault, holder of every `_ADMIN` role plus direct
/// action roles on the chain's authoriser.
/// @param serviceSigner The chain's issuance service EOA, granted the
/// DEPOSIT / WITHDRAW / CERTIFY action roles.
struct ChainPrincipals {
    string network;
    address tokenOwnerSafe;
    address serviceSigner;
}

/// @notice No principal set is defined for the supplied network name.
/// Deliberately a typed revert rather than a zero-filled return: a lookup
/// for a network we never defined principals for must never be readable as
/// "principals pending hydration".
/// @param network The network name that has no principals entry.
error UnknownPrincipalsNetwork(string network);

/// @title LibChainPrincipals
/// @notice Per-chain principal tables for every network in
/// `LibStoxDeployNetworks.supportedNetworks()`. Consumers that assert or
/// author role grants (`LibAuthoriserInvariants`, the bootstrap scripts, the
/// cross-chain parity pin) take a `ChainPrincipals` value instead of
/// hardcoding Base's addresses, which is what makes the grant map
/// chain-parametric while the structure stays pinned in one place.
/// @dev Both principal addresses are known deterministic constants for
/// every supported chain (the Safe via its reproduced Base address, the
/// signer shared with Base), so a `ChainPrincipals` is never "pending" —
/// it is source-pinned, not runtime-hydrated. Whether a chain has actually
/// been BOOTSTRAPPED on-chain (Safe deployed + policy-aligned, authoriser
/// clone deployed, tokens deployed) is a separate question answered by the
/// deploy-artifact pins (`LibProdDeployV4`'s clone pin, the per-chain token
/// table) and by live-code assertions in `LibSafeInvariants` /
/// `LibInvariants`, not by this lib.
library LibChainPrincipals {
    /// @notice The Base issuance service EOA. Granted `DEPOSIT` (block
    /// 41797262), `WITHDRAW` (block 41797281) and `CERTIFY` (block 41797297)
    /// on the live Base authoriser shortly after the first service was
    /// provisioned. Moved here from `LibAuthoriserInvariants` (which
    /// re-exports it as `GRANTEE_SERVICE_1C66`) so the per-chain principal
    /// tables own the per-chain addresses.
    /// https://basescan.org/address/0x1c66d6708914c40239d54919320b4c48cae3d1a9
    address internal constant SERVICE_SIGNER_BASE = 0x1c66D6708914C40239D54919320b4C48cAE3D1A9;

    /// @notice The Ethereum mainnet ST0x token-owner Safe. Deterministically
    /// the SAME address as Base (Josh, 2026-07-07: reproduce the Safe at its
    /// Base address on Ethereum — Option A). The address is CREATE2-fixed by
    /// the genesis creation params pinned in `LibStoxSafeGenesis`, and
    /// `DeploySafeEthereumTest` proves the reproduction lands here on a live
    /// Ethereum fork — so this is a deterministic pin, not a placeholder, the
    /// same way the Zoltu core addresses in `LibProdDeployV4` are pinned
    /// before their on-chain deploy. The Safe's on-chain EXISTENCE (and its
    /// policy alignment to Base) is a separate bootstrap step, asserted at
    /// use-time by `LibSafeInvariants` against live code — not encoded here.
    address internal constant TOKEN_OWNER_SAFE_ETHEREUM = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;

    /// @notice The Ethereum mainnet issuance service EOA.
    /// @dev Ethereum reuses the Base issuance service signer for now (Josh,
    /// 2026-07-07). Kept as its own constant rather than aliasing
    /// `SERVICE_SIGNER_BASE` at the call sites so it can diverge later —
    /// point this at a distinct Ethereum signer with a one-line edit — but
    /// the value today is deliberately identical to Base.
    address internal constant SERVICE_SIGNER_ETHEREUM = SERVICE_SIGNER_BASE;

    /// @notice Base's principal set — the live production principals every
    /// current-state invariant validates against.
    /// @return principals Base's `ChainPrincipals`.
    function base() internal pure returns (ChainPrincipals memory principals) {
        principals = ChainPrincipals({
            network: LibRainDeploy.BASE,
            tokenOwnerSafe: LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,
            serviceSigner: SERVICE_SIGNER_BASE
        });
    }

    /// @notice Ethereum mainnet's principal set — the same token-owner Safe
    /// address and service signer as Base (matched-address Safe + shared
    /// signer). Concrete pins; the Safe's on-chain existence is a bootstrap
    /// step asserted at use-time, not represented here.
    /// @return principals Ethereum's `ChainPrincipals`.
    function ethereum() internal pure returns (ChainPrincipals memory principals) {
        principals = ChainPrincipals({
            network: LibStoxDeployNetworks.ETHEREUM,
            tokenOwnerSafe: TOKEN_OWNER_SAFE_ETHEREUM,
            serviceSigner: SERVICE_SIGNER_ETHEREUM
        });
    }

    /// @notice Principal-set lookup by network name. Reverts
    /// `UnknownPrincipalsNetwork` for any network without a defined table —
    /// never falls back to another chain's principals, mirroring the
    /// registry-miss-is-a-typed-failure invariant the multichain issuance
    /// design pins (a grant authored against the wrong chain's Safe is the
    /// catastrophic failure mode this lookup exists to prevent).
    /// @param network The rain-deploy / foundry.toml network name.
    /// @return principals The network's `ChainPrincipals`.
    function forNetwork(string memory network) internal pure returns (ChainPrincipals memory principals) {
        bytes32 key = keccak256(bytes(network));
        if (key == keccak256(bytes(LibRainDeploy.BASE))) {
            return base();
        }
        if (key == keccak256(bytes(LibStoxDeployNetworks.ETHEREUM))) {
            return ethereum();
        }
        revert UnknownPrincipalsNetwork(network);
    }
}
