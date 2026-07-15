// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibMigrationInvariant} from "../../../../src/lib/LibMigrationInvariant.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibProdAuthoriserClones} from "../../../../src/lib/LibProdAuthoriserClones.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibTokenInvariants} from "../../../../src/lib/LibTokenInvariants.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title StoxProdV4PostSwapTest
/// @notice Post-deploy + post-swap integrity pin for V4 on-chain state.
/// Two pin layers:
///
/// **Layer 1 — V4 bytecode integrity (per-network).** The deterministic V4
/// receipt vault implementation and the V4 corporate-actions facet must exist
/// at their post-rebuild Zoltu addresses with the audited V4 codehash on every
/// EVM network the ST0x deploy targets. Since V4 is only Zoltu-deployed on
/// Base today, the per-network check reads each address's `codehash` and
/// gates it through `LibMigrationInvariant`: either `bytes32(0)` (impl
/// undeployed) or the pinned V4 codehash is accepted until
/// `V4_CROSS_NETWORK_DEPLOY_DEADLINE`; only the pinned codehash is
/// accepted after. If the impl has not been redeployed on a network by the
/// deadline, cron red-lines against that network.
///
/// **Layer 2 — Authoriser swap window (Base only).** Every production
/// receipt vault reports either the V3 authoriser (`LibAuthoriserInvariants.
/// STOX_PROD_AUTHORISER`) or the pinned V4 clone
/// (`LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_BASE`), gated by
/// `LibMigrationInvariant` against `V4_SWAP_DEADLINE`. Before the deadline
/// both states pass; after the deadline only the V4 clone is accepted. Base-
/// only because no other network carries live production receipt vaults.
///
/// When (and only when) the clone pin is hydrated the additional invariants
/// on the clone itself — deployed codehash matches the pin, grant map
/// matches `LibAuthoriserInvariants.expectedGrants()` — are enforced. That
/// keeps the check from tautologically asserting on `address(0)` while the
/// pin is still a placeholder.
///
/// @dev Fork tests use an unpinned Base head fork so `block.timestamp` is
/// real and cron picks up the deadline transition automatically.
contract StoxProdV4PostSwapTest is Test {
    /// @notice Unix timestamp past which every network the ST0x deploy
    /// targets must carry the V4 receipt vault impl + corporate-actions
    /// facet at their Zoltu addresses with the pinned codehash.
    /// `2026-11-01T00:00:00Z`.
    /// @dev PLACEHOLDER — set to the operator SLA for the cross-network V4
    /// Zoltu redeploy. Adjust before merge if the intended cut-off is
    /// different. The Base-side swap deadline lives in
    /// `LibProdDeployV4.V4_SWAP_DEADLINE` (shared with
    /// `LibInvariants.assertAll`'s authoriser leg).
    uint256 internal constant V4_CROSS_NETWORK_DEPLOY_DEADLINE = 1_793_491_200;

    /// @notice Assert both V4 artifacts (receipt vault impl + corporate-
    /// actions facet) are either undeployed (`codehash == 0`) or deployed
    /// with the pinned codehash on the active fork, gated by
    /// `V4_CROSS_NETWORK_DEPLOY_DEADLINE`. Before the deadline both states
    /// pass; after the deadline only the pinned codehash is accepted.
    function checkAllV4OnChain() internal view {
        LibMigrationInvariant.assertMigration(
            "STOX_RECEIPT_VAULT_0_1_1.codehash",
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1.codehash,
            bytes32(0),
            LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_1,
            V4_CROSS_NETWORK_DEPLOY_DEADLINE
        );

        LibMigrationInvariant.assertMigration(
            "STOX_CORPORATE_ACTIONS_FACET_0_1_1.codehash",
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_1.codehash,
            bytes32(0),
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_0_1_1,
            V4_CROSS_NETWORK_DEPLOY_DEADLINE
        );
    }

    /// @notice Assert the vault-authoriser transition on Base: every prod
    /// receipt vault reports V3 authoriser or V4 clone up to
    /// `LibProdDeployV4.V4_SWAP_DEADLINE`, only V4 clone after. Once the
    /// clone pin is hydrated (address non-zero), additionally assert the
    /// clone's codehash pin + full grant map (the 11 `expectedGrants()`
    /// pairs plus all 7 auto-granted `_ADMIN` roles on the Safe, covering
    /// the two corporate-action admins the lib map doesn't carry).
    /// Base-only.
    function checkAuthoriserSwapWindowOnBase() internal view {
        address v4Clone = LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_BASE;

        // Every prod receipt vault reports V3 authoriser (pre) or V4 clone
        // (post) — the same migration-window leg `LibInvariants.assertAll`
        // composes.
        LibTokenInvariants.assertUniformAuthoriserMigration(
            LibAuthoriserInvariants.STOX_PROD_AUTHORISER, v4Clone, LibProdDeployV4.V4_SWAP_DEADLINE
        );

        // Once the clone pin is hydrated, the clone must be deployed at
        // that address with the pinned codehash and carry the expected
        // grant map exactly. Before hydration `v4Clone` is `address(0)`,
        // there is no clone to assert on, and these checks are skipped —
        // the migration invariant above still enforces the swap by the
        // deadline (via the `pre != post` branch), so the checks are not
        // load-bearing while the pin is a placeholder.
        if (v4Clone != address(0)) {
            assertTrue(v4Clone.code.length > 0, "V4 authoriser clone not deployed");
            assertEq(
                v4Clone.codehash,
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH,
                "V4 authoriser clone codehash mismatch"
            );

            IAccessControl cloneAcl = IAccessControl(v4Clone);

            // The 11 pairs the invariant lib pins (5 V3-era admins + 6
            // operational grants).
            RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants();
            for (uint256 i = 0; i < grants.length; i++) {
                assertTrue(cloneAcl.hasRole(grants[i].role, grants[i].grantee), "V4 clone missing expected grant");
            }

            // All 7 auto-granted `_ADMIN` roles held by the Safe — covers
            // the two corporate-action admins (`SCHEDULE_...` /
            // `CANCEL_CORPORATE_ACTION_ADMIN`) that `expectedGrants()`
            // doesn't carry (V4-only roles granted to the Safe by the
            // clone-deploy broadcast, per the RAI-731 decision).
            bytes32[7] memory adminRoles = [
                keccak256("CERTIFY_ADMIN"),
                keccak256("CONFISCATE_RECEIPT_ADMIN"),
                keccak256("CONFISCATE_SHARES_ADMIN"),
                keccak256("DEPOSIT_ADMIN"),
                keccak256("WITHDRAW_ADMIN"),
                keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN"),
                keccak256("CANCEL_CORPORATE_ACTION_ADMIN")
            ];
            address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
            for (uint256 i = 0; i < adminRoles.length; i++) {
                assertTrue(cloneAcl.hasRole(adminRoles[i], safe), "Safe missing auto-granted admin role on V4 clone");
            }
        }
    }

    /// V4 implementations MUST be deployed on Arbitrum.
    function testProdDeployArbitrumV4() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        checkAllV4OnChain();
    }

    /// V4 implementations MUST be deployed on Base + every live prod vault
    /// reports V3 or V4 clone as authoriser, gated by `V4_SWAP_DEADLINE`.
    function testProdDeployBaseV4() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        checkAllV4OnChain();
        checkAuthoriserSwapWindowOnBase();
    }

    /// V4 implementations MUST be deployed on Base Sepolia.
    function testProdDeployBaseSepoliaV4() external {
        vm.createSelectFork(LibRainDeploy.BASE_SEPOLIA);
        checkAllV4OnChain();
    }

    /// V4 implementations MUST be deployed on Flare.
    function testProdDeployFlareV4() external {
        vm.createSelectFork(LibRainDeploy.FLARE);
        checkAllV4OnChain();
    }

    /// V4 implementations MUST be deployed on Polygon.
    function testProdDeployPolygonV4() external {
        vm.createSelectFork(LibRainDeploy.POLYGON);
        checkAllV4OnChain();
    }
}
