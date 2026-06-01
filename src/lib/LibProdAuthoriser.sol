// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibProdSafes} from "./LibProdSafes.sol";

/// @title LibProdAuthoriser
/// @notice ST0x production authoriser constants on Base: the live clone, its
/// current (pre-V3) implementation, and the pinned `(role, grantee)` map
/// folded from `RoleGranted` / `RoleRevoked` events on Base. Consumed by the
/// authoriser invariant library for pre-flight and fork-test verification —
/// the constants here are the source of truth, and the fork test cross-checks
/// them against the chain.
///
/// The live authoriser is an EIP-1167 minimal-proxy clone, not upgradeable.
/// Adding corporate-action permissions requires deploying a new clone of the
/// V3 implementation
/// (`LibProdDeployV3.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1`),
/// mirroring every grant pinned below onto it, then calling `setAuthorizer`
/// on each of the production receipt vaults.
library LibProdAuthoriser {
    /// @notice Live ST0x authoriser clone on Base. Every production receipt
    /// vault's `authorizer()` returns this address.
    /// https://basescan.org/address/0x35f9fa9d80aaf2b0fb27f0ff015641b3408d7456
    address constant STOX_PROD_AUTHORISER = 0x35f9fA9d80aAF2B0fB27f0FF015641B3408d7456;

    /// @notice The pre-V3 implementation behind the live clone. A base
    /// `OffchainAssetReceiptVaultAuthorizerV1` from rain-vats that predates
    /// the corporate-action role-admin extension. Not in any deploy lib —
    /// pinned here so the invariant can prove the clone has not silently
    /// re-pointed to a different impl.
    /// https://basescan.org/address/0x2b4a510c3619d5e888095bfe9f95902d32da5556
    address constant STOX_PROD_AUTHORISER_IMPL_PRE_V3 = 0x2B4A510c3619d5E888095BFE9f95902D32dA5556;

    /// @notice The V4 production authoriser clone — the EIP-1167 minimal
    /// proxy of `StoxOffchainAssetReceiptVaultAuthorizerV1` (the corporate-
    /// action-aware authoriser) that the V3 receipt vault upgrade script
    /// rewires every production receipt vault onto via `setAuthorizer`. The
    /// impl is `LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_TBD`.
    ///
    /// **PLACEHOLDER** until the clone is deployed against the V4 impl as a
    /// one-off ops step (initialized with `STOX_TOKEN_OWNER_SAFE` as
    /// `initialAdmin`, then the non-admin grants from `expectedGrants()` are
    /// mirrored onto it). The clone's address is fixed once deployed but is
    /// not deterministic ahead of time (Rain `CloneFactory` uses
    /// non-deterministic `Clones.clone`); the post-deploy edit drops the
    /// real address in place of `address(0)` here.
    address constant STOX_PROD_AUTHORISER_V4_CLONE = address(0);

    /// @notice The pinned EIP-1167 runtime codehash for
    /// `STOX_PROD_AUTHORISER_V4_CLONE`. Deterministic from the V4 impl
    /// address embedded in the minimal-proxy runtime
    /// (`363d3d373d3d3d363d73<impl>5af43d82803e903d91602b57fd5bf3`); the
    /// invariant uses it to prove the clone hasn't been etched over.
    ///
    /// **PLACEHOLDER** — fill in once the V4 impl address is known and the
    /// clone is deployed. Easiest path: compute via
    /// `keccak256(abi.encodePacked(hex"363d3d373d3d3d363d73", v4Impl, hex"5af43d82803e903d91602b57fd5bf3"))`.
    bytes32 constant STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH = bytes32(0);

    /// @notice The ST0x token-owner Safe — holds every `_ADMIN` role on the
    /// live authoriser (set at init) and was later granted DEPOSIT, WITHDRAW
    /// and CERTIFY as a privileged operator. Identical to
    /// `LibProdSafes.STOX_TOKEN_OWNER_SAFE`; re-exported as a grantee
    /// constant for call-site clarity.
    address constant GRANTEE_TOKEN_OWNER_SAFE = LibProdSafes.STOX_TOKEN_OWNER_SAFE;

    /// @notice External service EOA granted `DEPOSIT` (block 41797262),
    /// `WITHDRAW` (block 41797281) and `CERTIFY` (block 41797297) shortly
    /// after the first service was provisioned. EOA, active service signer.
    /// @dev TODO: confirm identity and rename.
    /// https://basescan.org/address/0x1c66d6708914c40239d54919320b4c48cae3d1a9
    address constant GRANTEE_SERVICE_1C66 = 0x1c66D6708914C40239D54919320b4C48cAE3D1A9;

    /// @notice The base role-admin hierarchy used by the live authoriser
    /// sets `<ROLE>_ADMIN` as the admin of each action role rather than
    /// `DEFAULT_ADMIN_ROLE`. Consequently no `DEFAULT_ADMIN_ROLE` grant was
    /// emitted at init and no address holds it. Pinned as the explicit
    /// expectation so the invariant flags any future grant of
    /// `DEFAULT_ADMIN_ROLE` as unexpected.
    bytes32 constant DEFAULT_ADMIN_ROLE = bytes32(0);

    /// @notice A pinned `(role, grantee)` pair on the live authoriser.
    struct RoleGrant {
        bytes32 role;
        address grantee;
    }

    /// @notice The full `(role, grantee)` map in effect on the live
    /// authoriser. The invariant test below cross-checks the live chain
    /// state against this list; any drift either way (missing grant on
    /// chain, unexpected grant on chain) trips the test.
    /// @dev Source of truth folded from `RoleGranted` / `RoleRevoked` event
    /// scan on Base. The 11 entries split into: 5 `_ADMIN` roles held by
    /// the token-owner Safe (set at init), 3 action roles for the service
    /// EOA, 3 action roles the Safe later granted itself for direct
    /// operational use.
    /// @return grants The pinned `(role, grantee)` pairs.
    function expectedGrants() internal pure returns (RoleGrant[] memory grants) {
        grants = new RoleGrant[](11);

        // Init grants (block 41715184) — Safe receives every `_ADMIN` role.
        grants[0] = RoleGrant(keccak256("DEPOSIT_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[1] = RoleGrant(keccak256("WITHDRAW_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[2] = RoleGrant(keccak256("CERTIFY_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[3] = RoleGrant(keccak256("CONFISCATE_SHARES_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[4] = RoleGrant(keccak256("CONFISCATE_RECEIPT_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);

        // Service EOA provisioned at blocks 41797262, 41797281, 41797297.
        grants[5] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_SERVICE_1C66);
        grants[6] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_SERVICE_1C66);
        grants[7] = RoleGrant(keccak256("CERTIFY"), GRANTEE_SERVICE_1C66);

        // Safe later granted itself the corresponding action roles (blocks
        // 42704120, 42704140, 44076075) for direct operational use.
        grants[8] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[9] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[10] = RoleGrant(keccak256("CERTIFY"), GRANTEE_TOKEN_OWNER_SAFE);
    }
}
