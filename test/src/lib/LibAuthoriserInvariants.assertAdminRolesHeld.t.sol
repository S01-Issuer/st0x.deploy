// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Clones} from "@openzeppelin-contracts-5.7.0/proxy/Clones.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibAuthoriserClone} from "../../../src/lib/LibAuthoriserClone.sol";
import {ExpectedGrantMissing, LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibStoxConfigFork} from "../../../src/lib/LibStoxConfigFork.sol";
import {RoleGrant} from "../../../src/lib/RoleGrant.sol";
import {LibAuthoriserInvariantsHarness} from "./LibAuthoriserInvariantsHarness.sol";

contract LibAuthoriserInvariantsAssertAdminRolesHeldTest is Test {
    LibAuthoriserInvariantsHarness internal harness;
    StoxOffchainAssetReceiptVaultAuthorizerV1 internal authoriser;
    address internal constant ADMIN = address(0xAD);

    function setUp() external {
        harness = new LibAuthoriserInvariantsHarness();
        LibStoxConfigFork.bindAuthoriserAdmin(vm, ADMIN);
        authoriser = StoxOffchainAssetReceiptVaultAuthorizerV1(
            Clones.clone(address(new StoxOffchainAssetReceiptVaultAuthorizerV1()))
        );
        authoriser.initialize(LibAuthoriserClone.cloneData());
    }

    function testPassesForTheBoundAdmin() external view {
        harness.callAssertAdminRolesHeld(address(authoriser), ADMIN);
    }

    function testFuzzRefusesAnotherHolder(address other) external {
        vm.assume(other != ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExpectedGrantMissing.selector, address(authoriser), keccak256("DEPOSIT_ADMIN"), other
            )
        );
        harness.callAssertAdminRolesHeld(address(authoriser), other);
    }

    /// Each `_ADMIN` role, renounced, is refused by name.
    function testFuzzRefusesEachMissingAdminRole(uint256 index) external {
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(address(0), ADMIN);
        bytes32 role = grants[bound(index, 0, LibAuthoriserInvariants.ADMIN_ROLE_COUNT - 1)].role;
        vm.prank(ADMIN);
        authoriser.renounceRole(role, ADMIN);
        vm.expectRevert(abi.encodeWithSelector(ExpectedGrantMissing.selector, address(authoriser), role, ADMIN));
        harness.callAssertAdminRolesHeld(address(authoriser), ADMIN);
    }
}
