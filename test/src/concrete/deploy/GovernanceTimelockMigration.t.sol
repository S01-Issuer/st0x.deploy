// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {LibAuthoriserInvariants, RoleGrant} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibMigrationInvariant, MigrationStateDrift} from "../../../../src/lib/LibMigrationInvariant.sol";
import {LibTokenInvariantsHarness} from "../../lib/LibTokenInvariantsHarness.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../../../src/lib/LibTokenInvariants.sol";

/// @title GovernanceTimelockMigrationTest
/// @notice Live-fork forcing function for the governance-timelock rollout,
/// per chain (Base + Ethereum). Two surfaces are asserted through the
/// migration window:
///
/// - **Vault ownership** — every production receipt vault's `owner()` is
///   either the chain's Safe (migration pending) or the chain's governance
///   timelock (migration landed), until
///   `GOVERNANCE_TIMELOCK_MIGRATION_DEADLINE`; from then on only the
///   timelock is accepted.
/// - **Authoriser `_ADMIN` roles** — each of the seven `_ADMIN` roles is
///   held EXCLUSIVELY by either the Safe (pending) or the timelock
///   (landed). Split holding ("both") and orphaned roles ("neither") are
///   drift and trip immediately, before or after the deadline.
///
/// While a chain's timelock pin is still a placeholder, the post-state is
/// unreachable (the pin IS the accepted post value), so the chain logs a
/// loud PENDING and the deadline forces the whole rollout — deploy
/// broadcast, pin hydration, Safe execution — not just the final step. If
/// the rollout has not landed by the deadline this suite red-lines cron
/// and forces an operator choice: execute, extend the deadline, or delete
/// the invariant.
///
/// @dev Unpinned head forks so `block.timestamp` is real — pinning a block
/// would freeze the deadline check (same rationale as
/// `BeaconOwnerMigrationPinTest`). When the migration executes on-chain,
/// the post-execution flip PR retires this suite's pending branch by
/// repointing the strict uniform-ownership invariants (`LibInvariants`
/// consumers) from the Safe to the timelock.
contract GovernanceTimelockMigrationTest is Test {
    /// @notice Unix timestamp past which only the timelock-governed
    /// post-state is accepted — the operator-SLA cut-off for the whole
    /// governance-timelock rollout. `2026-10-01T00:00:00Z`. A later PR can
    /// move it earlier to tighten the forcing function or later to loosen
    /// it if the SLA shifts.
    uint256 internal constant GOVERNANCE_TIMELOCK_MIGRATION_DEADLINE = 1_790_812_800;

    /// @notice Sentinel "holder" reported when BOTH the Safe and the
    /// timelock hold an `_ADMIN` role. Never a legitimate on-chain state
    /// (the migration bundle is atomic), so it must trip
    /// `MigrationStateDrift` regardless of the deadline.
    address internal constant BOTH_HOLD_SENTINEL = address(0xB077);

    /// @notice Sentinel "holder" reported when NEITHER the Safe nor the
    /// timelock holds an `_ADMIN` role — an orphaned admin surface, the
    /// worst drift class this suite can see.
    address internal constant NEITHER_HOLDS_SENTINEL = address(0xDEAD);

    /// @notice The seven `_ADMIN` role hashes, sliced from the master grant
    /// map (sentinel principals — only the role hashes are read).
    function adminRoles() internal pure returns (bytes32[] memory roles) {
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(address(0), address(1));
        roles = new bytes32[](7);
        for (uint256 i = 0; i < 7; i++) {
            roles[i] = grants[i].role;
        }
    }

    /// @notice Assert the full migration window for one chain: vault
    /// ownership and exclusive `_ADMIN` holding, Safe-or-timelock until the
    /// deadline, timelock-only after.
    /// @param tokens The chain's production token table.
    /// @param safe The chain's token-owner Safe (the pre-state).
    /// @param timelock The chain's governance timelock pin (the post-state;
    /// `address(0)` while unhydrated, making the post-state unreachable and
    /// the deadline binding on the whole rollout).
    /// @param authoriser The chain's V4 authoriser clone.
    function assertChainMigrationWindow(
        TokenInstance[] memory tokens,
        address safe,
        address timelock,
        address authoriser
    ) internal {
        if (timelock == address(0)) {
            emit log("PENDING: governance timelock not yet deployed/pinned on this chain - dispatch 20260729-deploy-governance-timelock, hydrate the LibTimelockInvariants pin, then execute the 20260729-migrate-governance-to-timelock bundle before the deadline");
        }

        LibTokenInvariants.assertUniformOwnershipMigration(
            tokens, safe, timelock, GOVERNANCE_TIMELOCK_MIGRATION_DEADLINE
        );

        bytes32[] memory roles = adminRoles();
        IAccessControl acl = IAccessControl(authoriser);
        for (uint256 i = 0; i < roles.length; i++) {
            bool safeHolds = acl.hasRole(roles[i], safe);
            bool timelockHolds = timelock != address(0) && acl.hasRole(roles[i], timelock);
            address holder;
            if (safeHolds && timelockHolds) {
                holder = BOTH_HOLD_SENTINEL;
            } else if (safeHolds) {
                holder = safe;
            } else if (timelockHolds) {
                holder = timelock;
            } else {
                holder = NEITHER_HOLDS_SENTINEL;
            }
            LibMigrationInvariant.assertMigration(
                "authoriser _ADMIN exclusive holder", holder, safe, timelock, GOVERNANCE_TIMELOCK_MIGRATION_DEADLINE
            );
        }
    }

    /// @notice Base's vaults and authoriser `_ADMIN` roles are inside the
    /// governance-timelock migration window. Runs against Base head so the
    /// deadline transition surfaces automatically on cron.
    function testBaseGovernanceInMigrationWindow() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertChainMigrationWindow(
            LibTokenInvariants.productionTokensBase(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE
        );
    }

    /// @notice Ethereum's vaults and authoriser `_ADMIN` roles are inside
    /// the governance-timelock migration window.
    function testEthereumGovernanceInMigrationWindow() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertChainMigrationWindow(
            LibTokenInvariants.productionTokensEthereum(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ETHEREUM,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM
        );
    }

    /// @notice A vault owned by neither side of the migration trips
    /// `MigrationStateDrift` immediately, deadline notwithstanding —
    /// proving the window is two-valued, not a free-for-all.
    function testOwnershipMigrationRejectsThirdOwner() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        address stranger = address(0xBAD);
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensBase();
        vm.mockCall(tokens[0].receiptVault, abi.encodeWithSignature("owner()"), abi.encode(stranger));

        LibTokenInvariantsHarness harness = new LibTokenInvariantsHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                MigrationStateDrift.selector,
                "receiptVault.owner()",
                bytes32(uint256(uint160(safe))),
                bytes32(uint256(uint160(address(0)))),
                bytes32(uint256(uint160(stranger)))
            )
        );
        harness.callAssertUniformOwnershipMigration(
            tokens, safe, LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK, GOVERNANCE_TIMELOCK_MIGRATION_DEADLINE
        );
    }
}
