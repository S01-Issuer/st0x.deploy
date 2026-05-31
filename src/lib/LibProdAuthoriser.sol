// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibProdSafes} from "./LibProdSafes.sol";

/// @title LibProdAuthoriser
/// @notice ST0x production authoriser constants on Base: the live clone, its
/// current (pre-V3) implementation, and the pinned `(role, grantee)` map
/// enumerated from `RoleGranted` / `RoleRevoked` event scan on 2026-05-31
/// (13 grants, 0 revokes). Consumed by the authoriser invariant library for
/// pre-flight and fork-test verification — the constants here are the source
/// of truth, and the fork test cross-checks them against the chain.
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

    /// @notice The ST0x token-owner Safe — holds every `_ADMIN` role on the
    /// live authoriser (set at init) and was later granted DEPOSIT, WITHDRAW
    /// and CERTIFY as a privileged operator. Identical to
    /// `LibProdSafes.STOX_TOKEN_OWNER_SAFE`; re-exported as a grantee
    /// constant for call-site clarity.
    address constant GRANTEE_TOKEN_OWNER_SAFE = LibProdSafes.STOX_TOKEN_OWNER_SAFE;

    /// @notice External service EOA granted `DEPOSIT` (block 41715293) and
    /// `WITHDRAW` (block 41715310) at authoriser commissioning. EOA, active
    /// service signer.
    /// @dev TODO: confirm whether this is the issuance bot or the liquidity
    /// bot signer and rename the constant accordingly. The address is
    /// authoritative; only the human-friendly name is open.
    /// https://basescan.org/address/0xbd41f40d91ee4e816ada1aa842e94aeb6b6385a6
    address constant GRANTEE_SERVICE_BD41 = 0xbd41F40D91eE4E816Ada1Aa842e94aEb6B6385a6;

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

    /// @notice The full pinned `(role, grantee)` map currently in effect on
    /// the live authoriser. Folded from the
    /// `RoleGranted` / `RoleRevoked` history on 2026-05-31: 13 grants, 0
    /// revokes. Pre-flight calls `hasRole(role, grantee)` for each pair;
    /// the fork test additionally scans the same events via `vm.rpc` and
    /// asserts the folded set equals this map exactly (catches both missing
    /// pins and unexpected additions).
    /// @return grants The exact `(role, grantee)` pairs currently in effect.
    function expectedGrants() internal pure returns (RoleGrant[] memory grants) {
        grants = new RoleGrant[](13);

        // Init grants (block 41715184) — Safe receives every `_ADMIN` role.
        grants[0] = RoleGrant(keccak256("DEPOSIT_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[1] = RoleGrant(keccak256("WITHDRAW_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[2] = RoleGrant(keccak256("CERTIFY_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[3] = RoleGrant(keccak256("CONFISCATE_SHARES_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[4] = RoleGrant(keccak256("CONFISCATE_RECEIPT_ADMIN"), GRANTEE_TOKEN_OWNER_SAFE);

        // First service provisioned at commissioning (blocks 41715293, 41715310).
        grants[5] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_SERVICE_BD41);
        grants[6] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_SERVICE_BD41);

        // Second service provisioned at blocks 41797262, 41797281, 41797297.
        grants[7] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_SERVICE_1C66);
        grants[8] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_SERVICE_1C66);
        grants[9] = RoleGrant(keccak256("CERTIFY"), GRANTEE_SERVICE_1C66);

        // Safe later granted itself the corresponding action roles (blocks
        // 42704120, 42704140, 44076075) for direct operational use.
        grants[10] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[11] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_TOKEN_OWNER_SAFE);
        grants[12] = RoleGrant(keccak256("CERTIFY"), GRANTEE_TOKEN_OWNER_SAFE);
    }
}
