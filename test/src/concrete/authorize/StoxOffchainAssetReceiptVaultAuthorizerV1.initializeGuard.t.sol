// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../../../../src/lib/LibCorporateAction.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain.vats/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1,
    SCHEDULE_CORPORATE_ACTION_ADMIN,
    CANCEL_CORPORATE_ACTION_ADMIN
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {ICLONEABLE_V2_SUCCESS} from "rain.factory/interface/ICloneableV2.sol";

/// @dev Overrides _initialize to return a non-success value, simulating
/// a parent initialization failure.
contract FailingSuperInitAuthorizer is StoxOffchainAssetReceiptVaultAuthorizerV1 {
    bytes32 public constant FAILURE_SENTINEL = bytes32(uint256(1));

    function _initialize(OffchainAssetReceiptVaultAuthorizerV1Config memory) internal override returns (bytes32) {
        return FAILURE_SENTINEL;
    }
}

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
