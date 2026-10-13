// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.15/src/lib/LibMigrationRegistry.sol";
import {LibRainDeploy} from "rain-deploy-0.1.15/src/lib/LibRainDeploy.sol";

import {LibAuthoriserInvariants} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibEuAuthoriserClone} from "../../../../src/lib/LibEuAuthoriserClone.sol";
import {LibRbacMigration} from "../../../../src/lib/LibRbacMigration.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../../../src/lib/LibTimelockInvariants.sol";

/// @title EuAuthoriserProdTest
/// @notice The pinned EU assets authoriser clone is live on every chain it was
/// deployed to, read against the chain rather than re-derived.
///
/// Its role state is the one the chain's migration record implies: the
/// `initialize` state until the Safe's grant-and-handover bundle executes, the
/// pinned EU map with the `_ADMIN` roles on the governance timelock after.
contract EuAuthoriserProdTest is Test {
    function assertChainEuAuthoriser() internal view {
        LibAuthoriserInvariants.assertEuAuthoriserDeployed(block.chainid);

        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        uint256 appliedAt = LibMigrationRegistry.applied(
            safe, LibRbacMigration.STOX_RBAC_NAMESPACE, LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER
        );
        if (appliedAt != 0) {
            LibAuthoriserInvariants.assertExpectedEuGrants(
                LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid),
                safe,
                LibTimelockInvariants.timelockForChainId(block.chainid),
                LibAuthoriserInvariants.GRANTEE_EU_MINTER
            );
        } else {
            LibAuthoriserInvariants.assertEuAuthoriserInitialState(block.chainid);
        }

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
}
