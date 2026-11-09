// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Initializable} from "@openzeppelin-contracts-upgradeable-5.7.0/proxy/utils/Initializable.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";
import {StoxAuthorizerInitTest} from "../../../lib/StoxAuthorizerInitTest.sol";

contract StoxOffchainAssetReceiptVaultAuthorizerV1SecondInitializeTest is StoxAuthorizerInitTest {
    address constant ADMIN = address(uint160(uint256(keccak256("ADMIN"))));

    function testSecondInitializeReverts(address newAdmin) external {
        vm.assume(newAdmin != address(0) && newAdmin != ADMIN);
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();
        authorizer.initialize(LibTestDeploy.authorizerData(vm, ADMIN));

        bytes memory data = LibTestDeploy.authorizerData(vm, newAdmin);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        authorizer.initialize(data);
    }
}
