// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibAuthoriserInvariants} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibMigrationInvariant} from "../../../../src/lib/LibMigrationInvariant.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
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
/// (`LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE`), gated by
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

    /// @notice Assert the post-swap authoriser state on Base: every prod
    /// receipt vault's `authorizer()` is the current production authoriser
    /// (`LibAuthoriserInvariants.STOX_PROD_AUTHORISER` — the V4 clone), and
    /// the clone itself validates via the shared invariant (codehash bound
    /// to the audited 0.1.1 impl + the master `expectedGrants()` map).
    /// Base-only.
    /// @dev RED until the `20260623` swap bundle executes on Base — every
    /// vault still reports the retired V3 authoriser until then. This PR
    /// merges after the swap; the red is the pre-authored post-state pin.
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
