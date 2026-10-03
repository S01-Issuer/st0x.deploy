// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibAuthoriserInvariants} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibMigrationInvariant} from "../../../../src/lib/LibMigrationInvariant.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibTokenInvariants} from "../../../../src/lib/LibTokenInvariants.sol";
import {LibRainDeploy} from "rain-deploy-0.1.11/src/lib/LibRainDeploy.sol";

/// @title StoxProdV4PostSwapTest
/// @notice Post-deploy + post-swap integrity pin for V4 on-chain state.
/// Two pin layers:
///
/// **Layer 1 — V4 bytecode integrity (per-network).** The V4 receipt vault
/// implementation and the V4 corporate-actions facet at their Zoltu
/// addresses: either `bytes32(0)` (undeployed) or the pinned V4 codehash is
/// accepted until `V4_CROSS_NETWORK_DEPLOY_DEADLINE`; only the pinned
/// codehash is accepted after.
///
/// **Layer 2 — Authoriser (Base only).** Every production receipt vault
/// reports the V4 authoriser clone
/// (`LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE`), which
/// `LibAuthoriserInvariants.STOX_PROD_AUTHORISER` aliases, and the clone
/// itself passes `LibAuthoriserInvariants.assertAll()`. Base only,
/// because no other network carries live production receipt vaults.
///
/// The clone's own invariants — deployed codehash against the pin, grant
/// map against `expectedGrants()` — are enforced only once the clone pin is
/// hydrated, so the check cannot tautologically assert on `address(0)` while
/// that pin is still a placeholder.
///
/// @dev Unpinned head forks so `block.timestamp` is real. A pinned block
/// would freeze the deadline comparison to that block's timestamp, so cron
/// would never see the transition.
contract StoxProdV4PostSwapTest is Test {
    /// @notice Unix timestamp (`2026-11-01T00:00:00Z`) past which every
    /// network the ST0x deploy targets must carry the V4 receipt vault impl
    /// + corporate-actions facet at their Zoltu addresses with the pinned
    /// codehash.
    /// @dev **PLACEHOLDER.** This is a guess at the operator SLA for the
    /// cross-network V4 Zoltu redeploy, not a date anyone has agreed. It
    /// needs confirming or changing before this merges, because once it
    /// passes with the redeploy outstanding it red-lines cron on every
    /// network that has not had one.
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

    /// @notice Assert the authoriser state on Base: every prod receipt
    /// vault's `authorizer()` is `LibAuthoriserInvariants.STOX_PROD_AUTHORISER`
    /// (the V4 clone), and the clone passes `LibAuthoriserInvariants.assertAll()`
    /// (pinned codehash + full `expectedGrants()` map).
    function checkPostSwapAuthoriserStateOnBase() internal view {
        LibTokenInvariants.assertUniformAuthoriser(LibAuthoriserInvariants.STOX_PROD_AUTHORISER);
        LibAuthoriserInvariants.assertAll();
    }

    /// V4 implementations MUST be deployed on Arbitrum.
    function testProdDeployArbitrumV4() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        checkAllV4OnChain();
    }

    /// V4 implementations MUST be deployed on Base + every live prod vault
    /// reports the current (V4) production authoriser.
    function testProdDeployBaseV4() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        checkAllV4OnChain();
        checkPostSwapAuthoriserStateOnBase();
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
