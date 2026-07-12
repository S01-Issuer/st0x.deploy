// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Clones} from "@openzeppelin-contracts-5.6.1/proxy/Clones.sol";
import {SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../../../../src/lib/LibCorporateAction.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    SCHEDULE_CORPORATE_ACTION_ADMIN,
    CANCEL_CORPORATE_ACTION_ADMIN
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {FailingSuperInitAuthorizer} from "./FailingSuperInitAuthorizer.sol";
import {ICLONEABLE_V2_SUCCESS} from "rain-factory-0.1.5/src/interface/ICloneableV2.sol";

contract StoxOffchainAssetReceiptVaultAuthorizerV1InitializeGuardTest is Test {
    address constant ADMIN = address(uint160(uint256(keccak256("ADMIN"))));

    /// When _initialize returns non-success, initialize returns that value
    /// and does NOT set up corporate action role admins.
    function testInitializeReturnsEarlyOnSuperFailure() external {
        FailingSuperInitAuthorizer impl = new FailingSuperInitAuthorizer();
        FailingSuperInitAuthorizer authorizer = FailingSuperInitAuthorizer(Clones.clone(address(impl)));

        bytes32 result =
            authorizer.initialize(abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: ADMIN})));

        // initialize returns the failure sentinel, not ICLONEABLE_V2_SUCCESS.
        assertEq(result, FailingSuperInitAuthorizer(address(impl)).FAILURE_SENTINEL());
        assertTrue(result != ICLONEABLE_V2_SUCCESS);

        // Role admins should NOT be set (default admin is bytes32(0)).
        assertEq(authorizer.getRoleAdmin(SCHEDULE_CORPORATE_ACTION), bytes32(0));
        assertEq(authorizer.getRoleAdmin(CANCEL_CORPORATE_ACTION), bytes32(0));

        // Admin should NOT have the corporate action admin roles.
        assertFalse(authorizer.hasRole(SCHEDULE_CORPORATE_ACTION_ADMIN, ADMIN));
        assertFalse(authorizer.hasRole(CANCEL_CORPORATE_ACTION_ADMIN, ADMIN));
    }
}
