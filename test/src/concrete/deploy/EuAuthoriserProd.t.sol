// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {IMigrationRegistryV2} from "rain-deploy-0.1.15/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.15/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.15/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "rain-deploy-0.1.15/src/lib/LibRainDeploy.sol";

import {LibAuthoriserInvariants, UnexpectedRetainedAdminGrant} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibEuAuthoriserClone} from "../../../../src/lib/LibEuAuthoriserClone.sol";
import {LibRbacMigration} from "../../../../src/lib/LibRbacMigration.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../../../src/lib/LibTimelockInvariants.sol";

/// @title EuAuthoriserProdTest
/// @notice The pinned EU assets authoriser clone is live on every chain it was
/// deployed to, read against the chain rather than re-derived.
///
/// The Safe's grant-and-handover bundle is required on every chain, so each
/// chain must carry its migration record and the post-bundle role state: the
/// pinned EU map, with the `_ADMIN` roles on the governance timelock and none
/// on the Safe. A chain whose bundle has not executed is red.
contract EuAuthoriserProdTest is Test {
    function assertChainEuAuthoriser() internal view {
        LibAuthoriserInvariants.assertEuAuthoriserDeployed(block.chainid);

        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        assertGt(
            LibMigrationRegistry.applied(
                safe, LibRbacMigration.STOX_RBAC_NAMESPACE, LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER
            ),
            0,
            "EU authoriser grant-and-handover recorded"
        );
        LibAuthoriserInvariants.assertExpectedEuGrants(
            LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid),
            safe,
            LibTimelockInvariants.timelockForChainId(block.chainid),
            LibAuthoriserInvariants.GRANTEE_EU_MINTER
        );

        address pinned = LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid);
        assertEq(
            pinned, LibEuAuthoriserClone.cloneDeployedAddress(block.chainid), "pin matches the derivation on chain"
        );
        assertEq(
            pinned.codehash,
            LibEuAuthoriserClone.cloneDeployedCodehash(),
            "the pinned clone carries the derived runtime"
        );
        assertTrue(
            pinned != LibAuthoriserInvariants.authoriserForChainId(block.chainid),
            "the EU clone is not the production clone"
        );
    }

    function testBaseEuAuthoriserDeployed() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertChainEuAuthoriser();
    }

    function testEthereumEuAuthoriserDeployed() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertChainEuAuthoriser();
    }

    function testHyperevmEuAuthoriserDeployed() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertChainEuAuthoriser();
    }

    function testRobinhoodEuAuthoriserDeployed() external {
        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        assertChainEuAuthoriser();
    }

    function testBscEuAuthoriserDeployed() external {
        vm.createSelectFork(LibStoxDeployNetworks.BSC);
        assertChainEuAuthoriser();
    }

    /// @notice External entry so an inverted test can expect the revert.
    function externalAssertChainEuAuthoriser() external view {
        assertChainEuAuthoriser();
    }

    /// Inverted: on Base the grant-and-handover is recorded, so a Safe still
    /// holding an `_ADMIN` role — able to grant action roles without the
    /// timelock's delay — is refused.
    function testBaseEuAuthoriserRejectsAdminRetainedBySafe() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address clone = LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        bytes32 role = keccak256("DEPOSIT_ADMIN");
        vm.mockCall(clone, abi.encodeCall(IAccessControl.hasRole, (role, safe)), abi.encode(true));
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRetainedAdminGrant.selector, clone, role, safe));
        this.externalAssertChainEuAuthoriser();
    }

    /// Inverted: Base's live role state is the post-bundle one, so with its
    /// migration record removed only the record check can refuse it.
    function testBaseEuAuthoriserRejectsMissingMigrationRecord() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        vm.mockCall(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            abi.encodeCall(
                IMigrationRegistryV2.applied,
                (safe, LibRbacMigration.STOX_RBAC_NAMESPACE, LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER)
            ),
            abi.encode(uint256(0))
        );
        vm.expectRevert(bytes("EU authoriser grant-and-handover recorded: 0 <= 0"));
        this.externalAssertChainEuAuthoriser();
    }
}
