// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {ExpectedGrantMissing, LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {RoleGrant} from "../../../src/lib/RoleGrant.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {StoxAuthorizerInitTest} from "../../lib/StoxAuthorizerInitTest.sol";
import {LibAuthoriserInvariantsHarness} from "./LibAuthoriserInvariantsHarness.sol";

contract LibAuthoriserInvariantsAssertAdminRolesHeldTest is StoxAuthorizerInitTest {
    LibAuthoriserInvariantsHarness internal harness;
    StoxOffchainAssetReceiptVaultAuthorizerV1 internal authoriser;
    address internal constant ADMIN = address(0xAD);

    function setUp() external {
        harness = new LibAuthoriserInvariantsHarness();
        authoriser = newAuthorizer();
        authoriser.initialize(LibTestDeploy.authorizerData(vm, ADMIN));
    }

    /// @notice The bound initial admin holds every `_ADMIN` role and passes.
    function testPassesForTheBoundAdmin() external view {
        harness.callAssertAdminRolesHeld(address(authoriser), ADMIN);
    }

    /// @notice Any other holder is refused on the first `_ADMIN` role.
    function testFuzzRefusesAnotherHolder(address other) external {
        vm.assume(other != ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExpectedGrantMissing.selector, address(authoriser), keccak256("DEPOSIT_ADMIN"), other
            )
        );
        harness.callAssertAdminRolesHeld(address(authoriser), other);
    }

    /// @notice Each `_ADMIN` role, renounced, is refused by name.
    function testRefusesEachMissingAdminRole() external {
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(address(0), ADMIN);
        for (uint256 i = 0; i < LibAuthoriserInvariants.ADMIN_ROLE_COUNT; i++) {
            uint256 snapshot = vm.snapshotState();
            bytes32 role = grants[i].role;
            vm.prank(ADMIN);
            authoriser.renounceRole(role, ADMIN);
            vm.expectRevert(abi.encodeWithSelector(ExpectedGrantMissing.selector, address(authoriser), role, ADMIN));
            harness.callAssertAdminRolesHeld(address(authoriser), ADMIN);
            vm.revertToState(snapshot);
        }
    }
}
