// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {LibAuthoriserInvariants, RoleGrant} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibMigrationInvariant, MigrationStateDrift} from "../../../../src/lib/LibMigrationInvariant.sol";
import {LibSafeInvariantsHarness} from "../../lib/LibSafeInvariantsHarness.sol";
import {LibTimelockInvariantsHarness} from "../../lib/LibTimelockInvariantsHarness.sol";
import {LibTokenInvariantsHarness} from "../../lib/LibTokenInvariantsHarness.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../../../src/lib/LibTokenInvariants.sol";

/// @title GovernanceTimelockMigrationTest
/// @notice Live-fork forcing function for the governance-timelock rollout,
/// per chain (Base + Ethereum + HyperEVM — every chain carrying production
/// tokens). Two surfaces are asserted through the migration window:
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

    /// @notice HyperEVM's vaults, beacons and authoriser `_ADMIN` roles are
    /// inside the same migration window. HyperEVM carries 29 live production
    /// tokens, so leaving it outside the deadline would let the chain with
    /// the newest deployment be the one chain still Safe-governed.
    /// @dev Soft-skips while `HYPEREVM_RPC_URL` is unprovisioned in CI
    /// (rainix is adding the `RPC_URL_HYPEREVM_FORK` slot, RAI-1511) — the
    /// same PENDING-log-and-return the multichain stack's HyperEVM suites
    /// use, since the static job bans `vm.skip`. The chain-map half of
    /// HyperEVM's coverage is asserted fork-free by
    /// `testEveryGovernedChainHasTimelockCoverage` below, so a missing RPC
    /// does not leave the chain wholly unasserted.
    function testHyperevmGovernanceInMigrationWindow() external {
        if (bytes(vm.envOr("HYPEREVM_RPC_URL", string(""))).length == 0) {
            emit log("PENDING: HYPEREVM_RPC_URL not available in this environment (RAI-1511)");
            return;
        }
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertChainMigrationWindow(
            LibTokenInvariants.productionTokensHyperEvm(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_HYPEREVM,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM
        );
    }

    /// @notice Chain ids ST0x governs today or is expected to govern.
    ///
    /// NOT a list of supported chains: an entry is INERT until that chain
    /// gains a pinned token-owner Safe. Listing a chain early costs nothing
    /// and is the whole point — a new chain cannot be onboarded past this
    /// guard without someone either adding its timelock arm or consciously
    /// deleting it from this list.
    /// @return ids The candidate chain ids.
    function governedChainCandidates() internal pure returns (uint256[] memory ids) {
        ids = new uint256[](3);
        ids[0] = LibSafeInvariants.BASE_CHAIN_ID;
        ids[1] = LibSafeInvariants.ETHEREUM_CHAIN_ID;
        ids[2] = LibSafeInvariants.HYPEREVM_CHAIN_ID;
    }

    /// @notice Every chain ST0x governs must be known to the governance
    /// timelock library. A chain is "governed" once it has a pinned
    /// token-owner Safe; from that point `timelockForChainId` must resolve
    /// it (even to an unhydrated `address(0)` pin) rather than reverting
    /// `UnsupportedChainForGovernanceTimelock`.
    ///
    /// This closes the gap left by keeping the governance-timelock rollout
    /// and the multichain (HyperEVM) rollout as independent stacks. Whichever
    /// merges second, the chain tables and the timelock's chain map must
    /// agree. Without this guard, a multichain stack landing first would put
    /// production tokens on a chain that `assertChainMigrationWindow` never
    /// walks — no vault ownership assertion, no beacon assertion, no
    /// deadline — and nothing would go red. The gap would be invisible
    /// precisely because the forcing function is enumerated per chain.
    ///
    /// @dev Deliberately triggers on the SAFE pin rather than on a populated
    /// token table, so it fires at chain bootstrap rather than at first
    /// token deploy. Eager is the right bias for a forcing function: the fix
    /// is to add a placeholder pin slot, exactly what Base and Ethereum
    /// carry today. Needs no fork — both resolvers are `pure`.
    function testEveryGovernedChainHasTimelockCoverage() external {
        LibSafeInvariantsHarness safeHarness = new LibSafeInvariantsHarness();
        LibTimelockInvariantsHarness timelockHarness = new LibTimelockInvariantsHarness();

        uint256[] memory ids = governedChainCandidates();
        for (uint256 i = 0; i < ids.length; i++) {
            // Not governed yet — nothing to cover, so the entry is inert.
            try safeHarness.callSafeForChainId(ids[i]) returns (address) {}
            catch {
                continue;
            }

            bool covered = true;
            try timelockHarness.callTimelockForChainId(ids[i]) returns (address) {}
            catch {
                covered = false;
            }
            assertTrue(
                covered,
                string.concat(
                    "chain ",
                    vm.toString(ids[i]),
                    " has a pinned token-owner Safe but no governance timelock arm: add it to",
                    " LibTimelockInvariants.timelockForChainId and to assertChainMigrationWindow's",
                    " per-chain tests, or the chain runs ungoverned by the timelock"
                )
            );
        }
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
