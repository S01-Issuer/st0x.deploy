// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.15/src/lib/LibMigrationRegistry.sol";
import {LibRainDeploy} from "rain-deploy-0.1.15/src/lib/LibRainDeploy.sol";

import {LibAuthoriserInvariants, RoleGrant} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibEuAuthoriserClone} from "../../../../src/lib/LibEuAuthoriserClone.sol";
import {LibEuAuthoriserMigration} from "../../../../src/lib/LibEuAuthoriserMigration.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../../../src/lib/LibTimelockInvariants.sol";

/// @title EuAuthoriserMigrationTest
/// @notice Live-fork pin of the EU assets authoriser's role state on every
/// chain it is cloned to, switched on the migration registry rather than
/// asserted unconditionally.
///
/// The clone is deployed with the chain's token-owner Safe as its only admin
/// and no action roles; the Safe bundle takes it to the pinned map and hands
/// the seven `_ADMIN` roles to the governance timelock. Both states are
/// correct production, one before the bundle executes and one after, so the
/// registry record of the grant-and-handover migration selects which one this
/// asserts — and both branches assert.
contract EuAuthoriserMigrationTest is Test {
    /// @notice Assert the EU authoriser state the active fork's migration
    /// record implies.
    /// @param label Human chain name, surfaced in assertion messages.
    /// @param chainId The chain the leg must be forked on.
    function assertEuAuthoriserRollout(string memory label, uint256 chainId) internal view {
        assertEq(block.chainid, chainId, string.concat(label, ": fork"));
        address safe = LibSafeInvariants.safeForChainId(chainId);
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        address clone = LibEuAuthoriserClone.cloneDeployedAddress(chainId);

        uint256 appliedAt = LibMigrationRegistry.applied(
            safe, LibEuAuthoriserMigration.EU_AUTHORISER_NAMESPACE, LibEuAuthoriserMigration.EU_AUTHORISER_MIGRATION
        );
        if (appliedAt != 0) {
            LibAuthoriserInvariants.assertExpectedGrants(
                clone, safe, timelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER
            );
        } else {
            assertPreBundleGrants(label, clone, safe, timelock);
        }
    }

    /// @notice The state `20261006-deploy-eu-authoriser` leaves and the Safe
    /// bundle has not yet moved: the Safe holds the seven `_ADMIN` roles and
    /// nothing else, every action role is ungranted, and the timelock holds
    /// nothing. Walks the same pinned map the post-state is asserted against,
    /// so the two cannot describe different role sets.
    /// @param label Human chain name, surfaced in assertion messages.
    /// @param clone The EU authoriser clone.
    /// @param safe The chain's token-owner Safe.
    /// @param timelock The chain's governance timelock.
    function assertPreBundleGrants(string memory label, address clone, address safe, address timelock) internal view {
        IAccessControl acl = IAccessControl(clone);
        RoleGrant[] memory grants =
            LibAuthoriserInvariants.expectedGrants(safe, timelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER);
        for (uint256 i = 0; i < grants.length; i++) {
            string memory where = string.concat(label, ": grant ", vm.toString(i));
            bool isAdminRole = i < LibAuthoriserInvariants.ADMIN_ROLE_COUNT;
            assertEq(acl.hasRole(grants[i].role, safe), isAdminRole, string.concat(where, " on the safe"));
            assertFalse(acl.hasRole(grants[i].role, timelock), string.concat(where, " on the timelock"));
            if (!isAdminRole) {
                assertFalse(acl.hasRole(grants[i].role, grants[i].grantee), string.concat(where, " on its grantee"));
            }
        }
    }

    function testEuAuthoriserRolloutBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertEuAuthoriserRollout("base", LibSafeInvariants.BASE_CHAIN_ID);
    }

    function testEuAuthoriserRolloutEthereum() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertEuAuthoriserRollout("ethereum", LibSafeInvariants.ETHEREUM_CHAIN_ID);
    }

    function testEuAuthoriserRolloutHyperEvm() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertEuAuthoriserRollout("hyperevm", LibSafeInvariants.HYPEREVM_CHAIN_ID);
    }

    function testEuAuthoriserRolloutRobinhood() external {
        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        assertEuAuthoriserRollout("robinhood", LibSafeInvariants.ROBINHOOD_CHAIN_ID);
    }

    function testEuAuthoriserRolloutBsc() external {
        vm.createSelectFork(LibStoxDeployNetworks.BSC);
        assertEuAuthoriserRollout("bsc", LibSafeInvariants.BSC_CHAIN_ID);
    }
}
