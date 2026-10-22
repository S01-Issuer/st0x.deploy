// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Clones} from "@openzeppelin-contracts-5.7.0/proxy/Clones.sol";
import {SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../../../../src/lib/LibCorporateAction.sol";
import {
    SCHEDULE_CORPORATE_ACTION_ADMIN,
    CANCEL_CORPORATE_ACTION_ADMIN
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibAuthoriserClone} from "../../../../src/lib/LibAuthoriserClone.sol";
import {LibStoxConfigFork} from "../../../../src/lib/LibStoxConfigFork.sol";
import {FAILURE_SENTINEL, FailingSuperInitAuthorizer} from "./FailingSuperInitAuthorizer.sol";

contract StoxOffchainAssetReceiptVaultAuthorizerV1InitializeGuardTest is Test {
    address constant ADMIN = address(uint160(uint256(keccak256("ADMIN"))));

    /// When the base `_initialize` returns non-success, initialize returns
    /// that value and does NOT set up corporate action role admins.
    function testInitializeReturnsEarlyOnSuperFailure() external {
        LibStoxConfigFork.bindAuthoriserAdmin(vm, ADMIN);
        FailingSuperInitAuthorizer impl = new FailingSuperInitAuthorizer();
        FailingSuperInitAuthorizer authorizer = FailingSuperInitAuthorizer(Clones.clone(address(impl)));

        bytes32 result = authorizer.initialize(LibAuthoriserClone.cloneData());

        assertEq(result, FAILURE_SENTINEL);

        assertEq(authorizer.getRoleAdmin(SCHEDULE_CORPORATE_ACTION), bytes32(0));
        assertEq(authorizer.getRoleAdmin(CANCEL_CORPORATE_ACTION), bytes32(0));

        assertFalse(authorizer.hasRole(SCHEDULE_CORPORATE_ACTION_ADMIN, ADMIN));
        assertFalse(authorizer.hasRole(CANCEL_CORPORATE_ACTION_ADMIN, ADMIN));
    }
}
