// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {console2} from "forge-std-1.16.2/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.10/src/lib/LibRainDeploy.sol";

import {LibAuthoriserInvariants, RoleGrant} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";
import {LibBeaconInvariantsHarness} from "../../lib/LibBeaconInvariantsHarness.sol";
import {LibMigrationInvariant, MigrationStateDrift} from "../../../../src/lib/LibMigrationInvariant.sol";
import {LibSafeInvariantsHarness} from "../../lib/LibSafeInvariantsHarness.sol";
import {LibTimelockInvariantsHarness} from "../../lib/LibTimelockInvariantsHarness.sol";
import {LibTokenInvariantsHarness} from "../../lib/LibTokenInvariantsHarness.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../../../src/lib/LibTokenInvariants.sol";

/// @notice The governance-timelock rollout deadline passed with this chain
/// still pre-rollout: the timelock is not deployed there, or the chain has no
/// production tokens to govern. Run the outstanding dispatches, extend the
/// deadline, or delete the invariant.
/// @param label The chain still pending.
error GovernanceTimelockRolloutOverdue(string label);

/// @title GovernanceTimelockMigrationTest
/// @notice Live-fork pin of the governance-timelock migration window, per
/// chain in `governedChainCandidates()`. A chain with a deployed timelock
/// and a hydrated token table is asserted through the full window; a chain
/// still pre-rollout takes the PENDING branch, which pins the timelock
/// derivation and refuses past `ROLLOUT_DEADLINE`. Three surfaces are
/// asserted through the window:
///
/// - **Vault ownership** — every production receipt vault's `owner()` is
///   either the chain's Safe or the chain's governance timelock until
///   `GOVERNANCE_TIMELOCK_MIGRATION_DEADLINE`; from then on only the
///   timelock is accepted.
/// - **Beacon ownership** — the same window over the chain's three in-use
///   upgrade beacons.
/// - **Authoriser `_ADMIN` roles** — each of the seven `_ADMIN` roles is
///   held exclusively by either the Safe or the timelock. Split holding
///   ("both") and orphaned roles ("neither") trip immediately, before or
///   after the deadline.
///
/// A zero timelock pin fails immediately, deadline notwithstanding: every
/// governed chain's pin is a pure function of its Safe pin.
///
/// @dev Unpinned head forks so `block.timestamp` is real.
contract GovernanceTimelockMigrationTest is Test {
    /// @notice Unix timestamp (`2026-10-01T00:00:00Z`) past which only the
    /// timelock-governed post-state is accepted.
    uint256 internal constant GOVERNANCE_TIMELOCK_MIGRATION_DEADLINE = 1_790_812_800;

    /// @notice Unix timestamp (`2026-12-01T00:00:00Z`) past which a chain
    /// may no longer be pre-rollout. The same bootstrap date as
    /// `StoxCrossChainParityTest.ROBINHOOD_PARITY_DEADLINE` /
    /// `BSC_PARITY_DEADLINE`; distinct from
    /// `GOVERNANCE_TIMELOCK_MIGRATION_DEADLINE`, which applies only to a
    /// chain that already has a timelock and tokens.
    uint256 internal constant ROLLOUT_DEADLINE = 1_796_083_200;

    /// @notice Sentinel "holder" reported when both the Safe and the
    /// timelock hold an `_ADMIN` role; trips `MigrationStateDrift`
    /// regardless of the deadline.
    address internal constant BOTH_HOLD_SENTINEL = address(0xB077);

    /// @notice Sentinel "holder" reported when neither the Safe nor the
    /// timelock holds an `_ADMIN` role.
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
    /// @param timelock The chain's governance timelock pin (the
    /// post-state); zero fails immediately.
    /// @param authoriser The chain's V4 authoriser clone.
    function assertChainMigrationWindow(
        TokenInstance[] memory tokens,
        address safe,
        address timelock,
        address authoriser
    ) internal view {
        assertNotEq(timelock, address(0), "governance timelock pin is zero: reverted or never-hydrated chain arm");

        LibTokenInvariants.assertUniformOwnershipMigration(
            tokens, safe, timelock, GOVERNANCE_TIMELOCK_MIGRATION_DEADLINE
        );

        LibBeaconInvariants.assertProdBeaconsOwnershipMigration(
            block.chainid, safe, timelock, GOVERNANCE_TIMELOCK_MIGRATION_DEADLINE
        );

        bytes32[] memory roles = adminRoles();
        IAccessControl acl = IAccessControl(authoriser);
        for (uint256 i = 0; i < roles.length; i++) {
            bool safeHolds = acl.hasRole(roles[i], safe);
            bool timelockHolds = acl.hasRole(roles[i], timelock);
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

    /// @notice Base's vaults, beacons and authoriser `_ADMIN` roles are
    /// inside the governance-timelock migration window.
    function testBaseGovernanceInMigrationWindow() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertChainMigrationWindow(
            LibTokenInvariants.productionTokensBase(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE
        );
    }

    /// @notice Ethereum's vaults, beacons and authoriser `_ADMIN` roles are
    /// inside the governance-timelock migration window.
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
    /// inside the governance-timelock migration window.
    /// @dev Forks unconditionally; needs `HYPEREVM_RPC_URL`.
    function testHyperevmGovernanceInMigrationWindow() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertChainMigrationWindow(
            LibTokenInvariants.productionTokensHyperEvm(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_HYPEREVM,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM
        );
    }

    /// @notice Log that a chain is still pre-rollout, and refuse once the
    /// rollout deadline has passed.
    /// @param label Human chain name.
    /// @param what What the chain is still waiting on.
    function pendingRollout(string memory label, string memory what) internal view {
        // The window is days wide; validator timestamp skew cannot change
        // which side of it a run lands on.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= ROLLOUT_DEADLINE) {
            revert GovernanceTimelockRolloutOverdue(label);
        }
        console2.log(string.concat("PENDING [", label, "]: ", what));
    }

    /// @notice Whether every triple in a token table is hydrated. A chain
    /// mid-bootstrap carries an all-placeholder table.
    /// @param tokens The table to inspect.
    /// @return Every address in the table is non-zero.
    function tokenTableHydrated(TokenInstance[] memory tokens) internal pure returns (bool) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (
                tokens[i].receipt == address(0) || tokens[i].receiptVault == address(0)
                    || tokens[i].wrappedTokenVault == address(0)
            ) {
                return false;
            }
        }
        return tokens.length > 0;
    }

    /// @notice `assertChainMigrationWindow` for a chain that may still be
    /// pre-rollout. The pin is asserted unconditionally: non-zero, and equal
    /// to the address the chain's own Safe derives. Only the live-state legs
    /// wait, and only until `ROLLOUT_DEADLINE`.
    /// @param label Human chain name, used in the PENDING logs.
    /// @param tokens The chain's production token table.
    /// @param safe The chain's token-owner Safe (the pre-state).
    /// @param timelock The chain's governance timelock pin (the post-state).
    /// @param authoriser The chain's V4 authoriser clone.
    function assertChainMigrationWindowOrPending(
        string memory label,
        TokenInstance[] memory tokens,
        address safe,
        address timelock,
        address authoriser
    ) internal view {
        assertNotEq(timelock, address(0), "governance timelock pin is zero: reverted or never-hydrated chain arm");
        assertEq(
            timelock,
            LibTimelockInvariants.expectedTimelockAddress(safe),
            string.concat(label, ": timelock pin does not match the address its own Safe derives")
        );

        if (timelock.code.length == 0) {
            pendingRollout(label, "governance timelock not deployed -> dispatch 20260729-deploy-governance-timelock");
            return;
        }

        if (!tokenTableHydrated(tokens)) {
            pendingRollout(label, "token table placeholder -> dispatch 20260807-deploy-missing-tokens");
            return;
        }

        assertChainMigrationWindow(tokens, safe, timelock, authoriser);
    }

    /// @notice Robinhood Chain's governance rollout: the pin and derivation
    /// are asserted, and the live-state legs are PENDING until
    /// `ROLLOUT_DEADLINE` while the chain is pre-rollout.
    function testRobinhoodGovernanceInMigrationWindow() external {
        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        assertChainMigrationWindowOrPending(
            "robinhood",
            LibTokenInvariants.productionTokensRobinhood(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ROBINHOOD,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ROBINHOOD,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD
        );
    }

    /// @notice BNB Smart Chain's governance rollout, on the same terms as the
    /// Robinhood Chain leg.
    function testBscGovernanceInMigrationWindow() external {
        vm.createSelectFork(LibStoxDeployNetworks.BSC);
        assertChainMigrationWindowOrPending(
            "bsc",
            LibTokenInvariants.productionTokensBsc(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_BSC,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_BSC,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_BSC
        );
    }

    /// @notice Chain ids ST0x governs or is expected to govern. An entry is
    /// inert until that chain gains a pinned token-owner Safe.
    /// @return ids The candidate chain ids.
    function governedChainCandidates() internal pure returns (uint256[] memory ids) {
        ids = new uint256[](5);
        ids[0] = LibSafeInvariants.BASE_CHAIN_ID;
        ids[1] = LibSafeInvariants.ETHEREUM_CHAIN_ID;
        ids[2] = LibSafeInvariants.HYPEREVM_CHAIN_ID;
        ids[3] = LibSafeInvariants.ROBINHOOD_CHAIN_ID;
        ids[4] = LibSafeInvariants.BSC_CHAIN_ID;
    }

    /// @notice Every chain with a pinned token-owner Safe resolves in
    /// `timelockForChainId` rather than reverting
    /// `UnsupportedChainForGovernanceTimelock`. The pin's value is asserted
    /// elsewhere (non-zero by `assertChainMigrationWindow`, derivation-equal
    /// by `testPinsMatchDerivedAddresses`); this guard is only about the arm
    /// existing.
    /// @dev Triggers on the Safe pin, not on a populated token table. Needs
    /// no fork: both resolvers are `pure`.
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
    /// `MigrationStateDrift` immediately, deadline notwithstanding.
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
                bytes32(uint256(uint160(LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK))),
                bytes32(uint256(uint160(stranger)))
            )
        );
        harness.callAssertUniformOwnershipMigration(
            tokens, safe, LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK, GOVERNANCE_TIMELOCK_MIGRATION_DEADLINE
        );
    }

    /// @notice A beacon owned by neither side of the migration trips
    /// `MigrationStateDrift` immediately, deadline notwithstanding.
    function testBeaconOwnershipMigrationRejectsThirdOwner() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        address stranger = address(0xBAD);
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        vm.mockCall(beacons[0], abi.encodeWithSignature("owner()"), abi.encode(stranger));

        LibBeaconInvariantsHarness harness = new LibBeaconInvariantsHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                MigrationStateDrift.selector,
                "beacon.owner()",
                bytes32(uint256(uint160(safe))),
                bytes32(uint256(uint160(LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK))),
                bytes32(uint256(uint160(stranger)))
            )
        );
        harness.callAssertProdBeaconsOwnershipMigration(
            block.chainid, safe, LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK, GOVERNANCE_TIMELOCK_MIGRATION_DEADLINE
        );
    }
}
