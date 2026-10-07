// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.15/src/lib/LibMigrationRegistry.sol";
import {LibRainDeploy} from "rain-deploy-0.1.15/src/lib/LibRainDeploy.sol";

import {GrantEuAuthoriserRoles} from "../../script/20261006-grant-eu-authoriser-roles.s.sol";
import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibEuAuthoriserClone} from "../../src/lib/LibEuAuthoriserClone.sol";
import {LibEuAuthoriserMigration} from "../../src/lib/LibEuAuthoriserMigration.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../../src/lib/LibSafeOps.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title GrantEuAuthoriserRolesProdTest
/// @notice The ordering property the grant bundle relies on, walked against
/// the live clone on every chain: no `_ADMIN` role is ever unheld, not even
/// between two transactions of the MultiSend.
///
/// It matters because the `_ADMIN` roles administer themselves — on the live
/// clone `getRoleAdmin(DEPOSIT_ADMIN)` is `DEPOSIT_ADMIN` — so a role that
/// becomes unheld can never be granted again by anyone. Atomicity does not
/// cover it: the batch reverts whole on failure, but a wrong-but-passing
/// order would land a clone whose action roles are frozen forever.
///
/// The walk only exists before the bundle executes — `preflight` requires the
/// Safe to still hold every `_ADMIN`, and the `applyMigration` the bundle
/// opens with is run-once — so the migration record selects which state is
/// asserted, as it does in `EuAuthoriserMigration.t.sol`.
contract GrantEuAuthoriserRolesProdTest is Test {
    /// @notice Assert the bundle state the active fork's migration record
    /// implies.
    /// @param label Human chain name, surfaced in assertion messages.
    /// @param chainId The chain the leg must be forked on.
    function assertGrantBundleRollout(string memory label, uint256 chainId) internal {
        assertEq(block.chainid, chainId, string.concat(label, ": fork"));
        address safe = LibSafeInvariants.safeForChainId(chainId);

        uint256 appliedAt = LibMigrationRegistry.applied(
            safe, LibEuAuthoriserMigration.EU_AUTHORISER_NAMESPACE, LibEuAuthoriserMigration.EU_AUTHORISER_MIGRATION
        );
        if (appliedAt != 0) {
            LibAuthoriserInvariants.assertExpectedGrants(
                LibEuAuthoriserClone.cloneDeployedAddress(chainId),
                safe,
                LibTimelockInvariants.timelockForChainId(chainId),
                LibAuthoriserInvariants.GRANTEE_EU_MINTER
            );
        } else {
            assertWalkNeverUnholdsAnAdmin(label);
        }
    }

    /// @notice Execute the bundle's transactions against the live clone in
    /// the order `grantBundle` puts them in, as the Safe, asserting after
    /// each one that every `_ADMIN` role is still held by the Safe or the
    /// timelock — the only two principals the bundle moves them between —
    /// and the pinned map once the walk is done.
    /// @param label Human chain name, surfaced in assertion messages.
    function assertWalkNeverUnholdsAnAdmin(string memory label) internal {
        GrantEuAuthoriserRoles script = new GrantEuAuthoriserRoles();
        (address clone, address safe, address timelock) = script.preflight();
        SafeTx[] memory txs = script.grantBundle(clone, safe, timelock);
        bytes32[7] memory admins = script.adminRoles();
        IAccessControl acl = IAccessControl(clone);

        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(IGnosisSafe(safe), txs[i].to, txs[i].data);
            for (uint256 j = 0; j < admins.length; j++) {
                assertTrue(
                    acl.hasRole(admins[j], safe) || acl.hasRole(admins[j], timelock),
                    string.concat(label, ": admin ", vm.toString(j), " unheld after transaction ", vm.toString(i))
                );
            }
        }

        LibAuthoriserInvariants.assertExpectedGrants(clone, safe, timelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER);
    }

    function testGrantBundleRolloutBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertGrantBundleRollout("base", LibSafeInvariants.BASE_CHAIN_ID);
    }

    function testGrantBundleRolloutEthereum() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertGrantBundleRollout("ethereum", LibSafeInvariants.ETHEREUM_CHAIN_ID);
    }

    function testGrantBundleRolloutHyperEvm() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertGrantBundleRollout("hyperevm", LibSafeInvariants.HYPEREVM_CHAIN_ID);
    }

    function testGrantBundleRolloutRobinhood() external {
        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        assertGrantBundleRollout("robinhood", LibSafeInvariants.ROBINHOOD_CHAIN_ID);
    }

    function testGrantBundleRolloutBsc() external {
        vm.createSelectFork(LibStoxDeployNetworks.BSC);
        assertGrantBundleRollout("bsc", LibSafeInvariants.BSC_CHAIN_ID);
    }
}
