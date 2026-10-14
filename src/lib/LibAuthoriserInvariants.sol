// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";
import {RoleGrant, ForbiddenGrantHeld} from "./RoleGrant.sol";

/// @notice An expected `(role, grantee)` pair is not held on the authoriser.
/// Surfaces the exact pair that breaks the role-grant invariant rather than
/// a generic mismatch.
/// @param authoriser The authoriser address inspected.
/// @param role The role that should be held.
/// @param grantee The grantee that should hold the role.
error ExpectedGrantMissing(address authoriser, bytes32 role, address grantee);

/// @notice The authoriser's runtime codehash does not match the pinned
/// EIP-1167 minimal-proxy codehash, i.e. the clone does not proxy the
/// audited implementation.
/// @param authoriser The authoriser inspected.
/// @param expected The pinned EIP-1167 codehash.
/// @param actual The codehash observed on-chain.
error AuthoriserImplCodehashMismatch(address authoriser, bytes32 expected, bytes32 actual);

/// @notice Dispatched against a chain without a hydrated authoriser pin.
/// @param chainId The active chain id.
error UnsupportedChainForAuthoriser(uint256 chainId);

/// @notice The active chain's V4 authoriser is not ready (unpinned, no code,
/// or the wrong codehash).
/// @param authoriser The authoriser address inspected.
error AuthoriserNotReady(address authoriser);

/// @notice The pinned EU assets authoriser clone has no code, or does not
/// carry the EIP-1167 codehash that proves which implementation it proxies.
/// @param clone The clone address inspected.
error EuAuthoriserNotReady(address clone);

/// @title LibAuthoriserInvariants
/// @notice Reusable invariants for the ST0x production authoriser on every
/// chain:
/// the grantee constants and the single master `(role, grantee)` map every
/// consumer asserts. Each assertion either returns silently when the
/// invariant holds against the live chain state or reverts with a typed
/// error that pinpoints the drift.
/// @dev The authoriser-of-record is the V4 clone, whose ADDRESS and
/// CODEHASH pins live in `LibProdDeployV4` (the generated deploy lib) —
/// this lib consumes them rather than carrying copies. `assertAll()`
/// validates the V4 clone: codehash equals
/// `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH` (the EIP-1167
/// runtime embedding the audited 0.1.1 authoriser impl, so a matching hash
/// proves which implementation the clone proxies) and the full
/// `expectedGrants()` map holds.
///
/// Composed into `LibInvariants.assertAll` alongside `LibSafeInvariants`
/// and `LibTokenInvariants`; individually callable via `assertAll()` for
/// the focused authoriser drift detector.
library LibAuthoriserInvariants {
    /// @notice A chain's V4 authoriser clone pin, raw: `address(0)` while the
    /// slot is a placeholder. Reverts for a chain without a slot rather than
    /// falling back to another chain's clone. The one chain-to-clone table;
    /// the deploy script and every invariant read it.
    /// @param chainId The chain id.
    /// @return The pinned clone, or zero for a placeholder slot.
    function authoriserForChainId(uint256 chainId) internal pure returns (address) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        }
        if (chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
        }
        if (chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM;
        }
        if (chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD;
        }
        if (chainId == LibSafeInvariants.BSC_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_BSC;
        }
        revert UnsupportedChainForAuthoriser(chainId);
    }

    /// @notice The EU assets authoriser clone on Base.
    /// https://basescan.org/address/0xdb9152e46c1d140db6a6f814461f21c571f3275e
    address internal constant STOX_EU_AUTHORISER_CLONE = address(0xDB9152e46c1D140DB6a6f814461f21c571F3275e);

    /// @notice The EU assets authoriser clone on Ethereum. Shared with
    /// HyperEVM, Robinhood Chain and BNB Smart Chain, which share the Safe
    /// the clone's init data carries as initial admin.
    address internal constant STOX_EU_AUTHORISER_CLONE_ETHEREUM = address(0x8Fc06579571A105C5a699FA11d95b9c73747f8eb);

    /// @notice The EU assets authoriser clone on HyperEVM.
    address internal constant STOX_EU_AUTHORISER_CLONE_HYPEREVM = STOX_EU_AUTHORISER_CLONE_ETHEREUM;

    /// @notice The EU assets authoriser clone on Robinhood Chain.
    address internal constant STOX_EU_AUTHORISER_CLONE_ROBINHOOD = STOX_EU_AUTHORISER_CLONE_ETHEREUM;

    /// @notice The EU assets authoriser clone on BNB Smart Chain.
    address internal constant STOX_EU_AUTHORISER_CLONE_BSC = STOX_EU_AUTHORISER_CLONE_ETHEREUM;

    /// @notice A chain's EU assets authoriser clone pin. Reverts for a chain
    /// without a slot rather than falling back to another chain's clone.
    /// @param chainId The chain id.
    /// @return The pinned clone.
    function euAuthoriserForChainId(uint256 chainId) internal pure returns (address) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) {
            return STOX_EU_AUTHORISER_CLONE;
        }
        if (chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            return STOX_EU_AUTHORISER_CLONE_ETHEREUM;
        }
        if (chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID) {
            return STOX_EU_AUTHORISER_CLONE_HYPEREVM;
        }
        if (chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID) {
            return STOX_EU_AUTHORISER_CLONE_ROBINHOOD;
        }
        if (chainId == LibSafeInvariants.BSC_CHAIN_ID) {
            return STOX_EU_AUTHORISER_CLONE_BSC;
        }
        revert UnsupportedChainForAuthoriser(chainId);
    }

    /// @notice Asserts a chain's pinned EU assets authoriser clone is deployed
    /// and proxies the audited implementation. Role state is not asserted here:
    /// it changes when the Safe bundle executes, and the deployment does not.
    /// @param chainId The chain id.
    function assertEuAuthoriserDeployed(uint256 chainId) internal view {
        address clone = euAuthoriserForChainId(chainId);
        if (clone.code.length == 0 || clone.codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH) {
            revert EuAuthoriserNotReady(clone);
        }
    }

    /// @notice Asserts a chain's EU clone is still in the state `initialize`
    /// left it in: the chain's token-owner Safe holds every `_ADMIN` role, the
    /// timelock holds none, and the EU minter holds neither action role. This
    /// is the pre-state the Safe bundle moves off; it goes red once the bundle
    /// executes, which is what the registry switch is for.
    /// @param chainId The chain id.
    function assertEuAuthoriserInitialState(uint256 chainId) internal view {
        address clone = euAuthoriserForChainId(chainId);
        address safe = LibSafeInvariants.safeForChainId(chainId);
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);

        RoleGrant[] memory grants = expectedEuGrants(timelock, GRANTEE_EU_MINTER, GRANTEE_SERVICE_3D0C);
        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            if (!IAccessControl(clone).hasRole(grants[i].role, safe)) {
                revert ExpectedGrantMissing(clone, grants[i].role, safe);
            }
            if (IAccessControl(clone).hasRole(grants[i].role, timelock)) {
                revert ForbiddenGrantHeld(clone, grants[i].role, timelock);
            }
        }

        if (IAccessControl(clone).hasRole(keccak256("DEPOSIT"), GRANTEE_EU_MINTER)) {
            revert ForbiddenGrantHeld(clone, keccak256("DEPOSIT"), GRANTEE_EU_MINTER);
        }
        if (IAccessControl(clone).hasRole(keccak256("WITHDRAW"), GRANTEE_EU_MINTER)) {
            revert ForbiddenGrantHeld(clone, keccak256("WITHDRAW"), GRANTEE_EU_MINTER);
        }
    }

    /// @notice The active chain's hydrated V4 authoriser clone, asserted
    /// deployed with the shared EIP-1167 codehash.
    /// @return authoriser The validated authoriser address.
    function activeChainAuthoriser() internal view returns (address authoriser) {
        authoriser = authoriserForChainId(block.chainid);
        if (
            authoriser == address(0) || authoriser.code.length == 0
                || authoriser.codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
        ) {
            revert AuthoriserNotReady(authoriser);
        }
    }

    /// @notice THE current production authoriser — the single entrypoint
    /// every invariant and script reads. Aliases the V4 clone pinned in
    /// `LibProdDeployV4` (the generated deploy lib is the single source
    /// for the address; this constant is the semantic name "current
    /// authoriser"). Every production receipt vault's `authorizer()` must
    /// return this address — an expectation that goes green when the
    /// `20260623` swap bundle executes on Base.
    /// https://basescan.org/address/0x315b16faa6ee413fabca877d3851b3818369f0cd
    address internal constant STOX_PROD_AUTHORISER = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;

    /// @notice The role-admin hierarchy sets `<ROLE>_ADMIN` as the admin of
    /// each action role rather than `DEFAULT_ADMIN_ROLE`. Consequently no
    /// `DEFAULT_ADMIN_ROLE` grant was emitted at init and no address holds
    /// it, and `forbiddenGrants` forbids it to every pinned grantee.
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);

    /// @notice The number of `_ADMIN` roles in the grant map — its LEADING
    /// slice, so `expectedGrants(...)[0..ADMIN_ROLE_COUNT)` are exactly the
    /// entries that track the admin holder. The slice's position and length
    /// are pinned by `testExpectedGrantsAdminHolderParameterisation`.
    uint256 internal constant ADMIN_ROLE_COUNT = 7;

    /// @notice The ST0x token-owner Safe — holds DEPOSIT, WITHDRAW and
    /// CERTIFY on the production authoriser as a privileged operator; the
    /// `_ADMIN` roles are on the governance timelock. Identical to
    /// `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE`; re-exported as a grantee
    /// constant for call-site clarity.
    address internal constant GRANTEE_TOKEN_OWNER_SAFE = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;

    /// @notice The RETIRED original service EOA — Fireblocks-custodied. It
    /// holds NOTHING on any chain's authoriser: its `DEPOSIT`, `WITHDRAW`
    /// and `CERTIFY` were revoked on every chain by the
    /// `20260810-revoke-fireblocks-service-signer` Safe bundles (executed
    /// Aug 2026), and `forbiddenGrants` forbids them so a re-grant
    /// red-lines cron. Kept as an audit-trail constant.
    /// https://basescan.org/address/0x1c66d6708914c40239d54919320b4c48cae3d1a9
    address internal constant GRANTEE_SERVICE_1C66 = 0x1c66D6708914C40239D54919320b4C48cAE3D1A9;

    /// @notice The service EOA: `CERTIFY` on each chain's authoriser, its
    /// direct `DEPOSIT` and `WITHDRAW` there retiring (`retiringGrants`), and
    /// `MINT` and `BURN` on the orchestrator. Same address on every chain.
    address internal constant GRANTEE_SERVICE_3D0C = 0x3d0CD66EFA66c05d86c3d4316B03eAE87ab9E8aE;

    /// @notice The production orchestrator instance, granted `DEPOSIT` and
    /// `WITHDRAW` on each chain's authoriser by
    /// `20260831-enable-orchestrator-roles` so the service signer can mint
    /// and burn through it. Same address on every chain.
    address internal constant GRANTEE_ORCHESTRATOR = LibProdDeployV4.ST0X_ORCHESTRATOR_INSTANCE;

    /// @notice The minter for the EU assets authoriser, holding `DEPOSIT` and
    /// `WITHDRAW` — mint and redeem — where the shared service signer holds
    /// them on the US authoriser. The EU clone is the same implementation at
    /// the same role structure; this address is the only thing that differs,
    /// which is why the map below is parameterised on it rather than restated.
    address internal constant GRANTEE_EU_MINTER = 0x0958d9E94D9D4139280947ACd86D4a50F13bfA8C;

    /// @notice The full `(role, grantee)` map in effect on the Base
    /// production authoriser: Base's token-owner Safe in the operational
    /// slots, Base's governance timelock holding the seven `_ADMIN` roles.
    /// @return grants The pinned `(role, grantee)` pairs for Base.
    function expectedGrants() internal pure returns (RoleGrant[] memory grants) {
        grants = expectedGrants(GRANTEE_TOKEN_OWNER_SAFE, LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
    }

    /// @notice The canonical `(role, grantee)` map the production authoriser
    /// must carry, parameterised on the chain's token-owner Safe and the
    /// holder of the seven `_ADMIN` roles — the chain's governance timelock
    /// in production; the Safe keeps its three direct action roles. The
    /// STRUCTURE is chain-agnostic: service signers are shared across chains,
    /// the Safe and timelock are per-chain. The single source of truth every
    /// live-state invariant asserts.
    /// @param tokenOwnerSafe The chain's token-owner Safe filling the
    /// operational Safe grantee slots.
    /// @param adminHolder The holder of the seven `_ADMIN` roles.
    /// @return grants The `(role, grantee)` pairs for that chain.
    function expectedGrants(address tokenOwnerSafe, address adminHolder)
        internal
        pure
        returns (RoleGrant[] memory grants)
    {
        grants = new RoleGrant[](13);

        // Init grants (block 41715184 on Base) — the admin holder receives
        // every `_ADMIN` (the Safe at init; the governance timelock once the
        // timelock migration executes).
        grants[0] = RoleGrant(keccak256("DEPOSIT_ADMIN"), adminHolder);
        grants[1] = RoleGrant(keccak256("WITHDRAW_ADMIN"), adminHolder);
        grants[2] = RoleGrant(keccak256("CERTIFY_ADMIN"), adminHolder);
        grants[3] = RoleGrant(keccak256("CONFISCATE_SHARES_ADMIN"), adminHolder);
        grants[4] = RoleGrant(keccak256("CONFISCATE_RECEIPT_ADMIN"), adminHolder);

        // The two corporate-action admins the 0.1.1 impl adds. On Base the
        // clone-deploy broadcast transferred them to the Safe alongside the
        // other five and renounced them from the deploy key.
        grants[5] = RoleGrant(keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN"), adminHolder);
        grants[6] = RoleGrant(keccak256("CANCEL_CORPORATE_ACTION_ADMIN"), adminHolder);

        // Safe holds the corresponding action roles (Base blocks 42704120,
        // 42704140, 44076075) for direct operational use.
        grants[7] = RoleGrant(keccak256("DEPOSIT"), tokenOwnerSafe);
        grants[8] = RoleGrant(keccak256("WITHDRAW"), tokenOwnerSafe);
        grants[9] = RoleGrant(keccak256("CERTIFY"), tokenOwnerSafe);

        grants[10] = RoleGrant(keccak256("CERTIFY"), GRANTEE_SERVICE_3D0C);
        grants[11] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_ORCHESTRATOR);
        grants[12] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_ORCHESTRATOR);
    }

    /// @notice The service signer's direct vault roles every chain's authoriser must have revoked.
    /// @return The `(role, grantee)` pairs to revoke.
    function retiringGrants() internal pure returns (RoleGrant[] memory) {
        RoleGrant[] memory grants = new RoleGrant[](2);
        grants[0] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_SERVICE_3D0C);
        grants[1] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_SERVICE_3D0C);
        return grants;
    }

    /// @notice The pairs the production authoriser must not carry.
    /// @param tokenOwnerSafe The chain's token-owner Safe.
    /// @param adminHolder The holder of the seven `_ADMIN` roles.
    /// @return The forbidden `(role, grantee)` pairs.
    function forbiddenGrants(address tokenOwnerSafe, address adminHolder) internal pure returns (RoleGrant[] memory) {
        RoleGrant[] memory retiring = retiringGrants();
        RoleGrant[] memory grants = new RoleGrant[](15 + retiring.length);
        address[5] memory principals =
            [tokenOwnerSafe, adminHolder, GRANTEE_SERVICE_1C66, GRANTEE_SERVICE_3D0C, GRANTEE_ORCHESTRATOR];
        for (uint256 i = 0; i < principals.length; i++) {
            grants[i] = RoleGrant(DEFAULT_ADMIN_ROLE, principals[i]);
        }
        grants[5] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_SERVICE_1C66);
        grants[6] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_SERVICE_1C66);
        grants[7] = RoleGrant(keccak256("CERTIFY"), GRANTEE_SERVICE_1C66);
        RoleGrant[] memory expected = expectedGrants(tokenOwnerSafe, adminHolder);
        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            grants[8 + i] = RoleGrant(expected[i].role, tokenOwnerSafe);
        }
        for (uint256 i = 0; i < retiring.length; i++) {
            grants[15 + i] = retiring[i];
        }
        return grants;
    }

    /// @notice The pairs a region's authoriser must not carry.
    /// @param tokenOwnerSafe The chain's token-owner Safe.
    /// @param adminHolder The holder of the seven `_ADMIN` roles.
    /// @param minter The region's wallet.
    /// @return The forbidden `(role, grantee)` pairs.
    function forbiddenEuGrants(address tokenOwnerSafe, address adminHolder, address minter)
        internal
        pure
        returns (RoleGrant[] memory)
    {
        RoleGrant[] memory expected = expectedEuGrants(adminHolder, minter, GRANTEE_SERVICE_3D0C);
        RoleGrant[] memory grants = new RoleGrant[](29);
        address[6] memory principals =
            [tokenOwnerSafe, adminHolder, GRANTEE_SERVICE_1C66, GRANTEE_SERVICE_3D0C, GRANTEE_ORCHESTRATOR, minter];
        for (uint256 i = 0; i < principals.length; i++) {
            grants[i] = RoleGrant(DEFAULT_ADMIN_ROLE, principals[i]);
        }
        grants[6] = RoleGrant(keccak256("DEPOSIT"), GRANTEE_SERVICE_1C66);
        grants[7] = RoleGrant(keccak256("WITHDRAW"), GRANTEE_SERVICE_1C66);
        grants[8] = RoleGrant(keccak256("CERTIFY"), GRANTEE_SERVICE_1C66);
        uint256 count = 9;
        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            grants[count++] = RoleGrant(expected[i].role, tokenOwnerSafe);
        }
        for (uint256 i = ADMIN_ROLE_COUNT; i < ADMIN_ROLE_COUNT * 2; i++) {
            grants[count++] = RoleGrant(expected[i].role, GRANTEE_ORCHESTRATOR);
            if (!mapAssigns(expected, expected[i].role, GRANTEE_SERVICE_3D0C)) {
                grants[count++] = RoleGrant(expected[i].role, GRANTEE_SERVICE_3D0C);
            }
        }
        return grants;
    }

    /// @notice A region's authoriser map: every `_ADMIN` on the admin holder
    /// and every operational role on that region's wallet. Distinct from the
    /// US production map, which additionally grants to the shared service
    /// signer and the orchestrator — a region's authoriser grants to that
    /// region's operators only.
    /// @param adminHolder The holder of the seven `_ADMIN` roles.
    /// @param minter The region's wallet, holding all seven operational roles.
    /// @param additionalCertifier A second `CERTIFY` holder alongside the
    /// region's wallet.
    /// @return grants The `(role, grantee)` pairs for that authoriser.
    function expectedEuGrants(address adminHolder, address minter, address additionalCertifier)
        internal
        pure
        returns (RoleGrant[] memory grants)
    {
        // Every `_ADMIN` on the admin holder, every operational role on the
        // region's wallet, and nothing else. `tokenOwnerSafe` is the writer
        // that executes the bundle, not a grantee: it holds the `_ADMIN`
        // roles only until it has granted with them and renounced.
        //
        // The seven pairs are the ones the live clone reports: for each role
        // below, `getRoleAdmin(role)` is the matching `_ADMIN`, checked on
        // the deployed 0.1.1 implementation rather than read off 0.2.4's
        // source, which declares only five of them.
        grants = new RoleGrant[](15);

        grants[0] = RoleGrant(keccak256("DEPOSIT_ADMIN"), adminHolder);
        grants[1] = RoleGrant(keccak256("WITHDRAW_ADMIN"), adminHolder);
        grants[2] = RoleGrant(keccak256("CERTIFY_ADMIN"), adminHolder);
        grants[3] = RoleGrant(keccak256("CONFISCATE_SHARES_ADMIN"), adminHolder);
        grants[4] = RoleGrant(keccak256("CONFISCATE_RECEIPT_ADMIN"), adminHolder);
        grants[5] = RoleGrant(keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN"), adminHolder);
        grants[6] = RoleGrant(keccak256("CANCEL_CORPORATE_ACTION_ADMIN"), adminHolder);

        grants[7] = RoleGrant(keccak256("DEPOSIT"), minter);
        grants[8] = RoleGrant(keccak256("WITHDRAW"), minter);
        grants[9] = RoleGrant(keccak256("CERTIFY"), minter);
        grants[10] = RoleGrant(keccak256("CONFISCATE_SHARES"), minter);
        grants[11] = RoleGrant(keccak256("CONFISCATE_RECEIPT"), minter);
        grants[12] = RoleGrant(keccak256("SCHEDULE_CORPORATE_ACTION"), minter);
        grants[13] = RoleGrant(keccak256("CANCEL_CORPORATE_ACTION"), minter);

        // An additional certifier alongside the region's wallet. `CERTIFY` is
        // the one operational role with a second holder; every other one is
        // the minter's alone.
        grants[14] = RoleGrant(keccak256("CERTIFY"), additionalCertifier);
    }

    /// @notice Assert the Base map (`expectedGrants()`) on the supplied
    /// authoriser. See the three-argument overload.
    /// @param authoriser The authoriser to validate.
    function assertExpectedGrants(address authoriser) internal view {
        assertExpectedGrants(authoriser, GRANTEE_TOKEN_OWNER_SAFE, LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
    }

    /// @notice Assert the supplied authoriser holds no
    /// `forbiddenGrants(tokenOwnerSafe, adminHolder)` pair other than the
    /// `retiringGrants`, and every `expectedGrants(tokenOwnerSafe,
    /// adminHolder)` pair. This is the assertion surface every production
    /// consumer calls with the chain's governance timelock as `adminHolder`.
    /// @param authoriser The authoriser to validate.
    /// @param tokenOwnerSafe The chain's token-owner Safe filling the
    /// operational Safe grantee slots.
    /// @param adminHolder The holder of the seven `_ADMIN` roles.
    function assertExpectedGrants(address authoriser, address tokenOwnerSafe, address adminHolder) internal view {
        assertNoForbiddenGrant(authoriser, forbiddenGrants(tokenOwnerSafe, adminHolder), retiringGrants());
        assertHeld(authoriser, expectedGrants(tokenOwnerSafe, adminHolder));
    }

    /// @notice Whether the map assigns `role` to `grantee`.
    /// @param grants The map.
    /// @param role The role to look for.
    /// @param grantee The grantee to look for.
    /// @return Whether the pair is in the map.
    function mapAssigns(RoleGrant[] memory grants, bytes32 role, address grantee) internal pure returns (bool) {
        for (uint256 i = 0; i < grants.length; i++) {
            if (grants[i].role == role && grants[i].grantee == grantee) {
                return true;
            }
        }
        return false;
    }

    /// @notice Revert on the first `forbidden` pair `target` holds, other than
    /// a pair in `exempt`.
    /// @param target The `AccessControl` contract.
    /// @param forbidden The pairs it must not hold.
    /// @param exempt The pairs left unasserted.
    function assertNoForbiddenGrant(address target, RoleGrant[] memory forbidden, RoleGrant[] memory exempt)
        internal
        view
    {
        for (uint256 i = 0; i < forbidden.length; i++) {
            if (mapAssigns(exempt, forbidden[i].role, forbidden[i].grantee)) {
                continue;
            }
            if (IAccessControl(target).hasRole(forbidden[i].role, forbidden[i].grantee)) {
                revert ForbiddenGrantHeld(target, forbidden[i].role, forbidden[i].grantee);
            }
        }
    }

    /// @notice Revert on the first `expected` pair `authoriser` does not hold.
    /// @param authoriser The authoriser.
    /// @param expected The pairs it must hold.
    function assertHeld(address authoriser, RoleGrant[] memory expected) internal view {
        for (uint256 i = 0; i < expected.length; i++) {
            if (!IAccessControl(authoriser).hasRole(expected[i].role, expected[i].grantee)) {
                revert ExpectedGrantMissing(authoriser, expected[i].role, expected[i].grantee);
            }
        }
    }

    /// @notice The same assertion for a region's authoriser: no
    /// `forbiddenEuGrants` pair and every `expectedEuGrants` pair.
    /// @param authoriser The authoriser to validate.
    /// @param tokenOwnerSafe The chain's token-owner Safe.
    /// @param adminHolder The holder of the seven `_ADMIN` roles.
    /// @param minter The region's wallet.
    function assertExpectedEuGrants(address authoriser, address tokenOwnerSafe, address adminHolder, address minter)
        internal
        view
    {
        assertNoForbiddenGrant(authoriser, forbiddenEuGrants(tokenOwnerSafe, adminHolder, minter), new RoleGrant[](0));
        assertHeld(authoriser, expectedEuGrants(adminHolder, minter, GRANTEE_SERVICE_3D0C));
    }

    /// @notice Full authoriser-side invariant bundle against the current
    /// production authoriser (`STOX_PROD_AUTHORISER`): its codehash equals
    /// the pinned EIP-1167 runtime embedding the audited 0.1.1 authoriser
    /// impl (proving which implementation the clone proxies), and the full
    /// `expectedGrants()` map holds. Pre-flight at the start of every
    /// migration script and prod-state fork test; if this passes silently
    /// the production authoriser is in its expected state.
    /// @dev No-arg; composed into `LibInvariants.assertAll`. The retired
    /// V3 clone is deliberately NOT asserted — nothing references it.
    function assertAll() internal view {
        bytes32 expected = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH;
        bytes32 actual = STOX_PROD_AUTHORISER.codehash;
        if (actual != expected) {
            revert AuthoriserImplCodehashMismatch(STOX_PROD_AUTHORISER, expected, actual);
        }
        assertExpectedGrants(STOX_PROD_AUTHORISER);
    }
}
