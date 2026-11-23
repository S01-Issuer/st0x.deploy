// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {
    UnknownAuthorizerConfigVersion,
    OffchainAssetReceiptVaultAuthorizerV1Config,
    OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CONFIG_V2_TAG
} from "rain-vats-0.2.20/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG
} from "rain-vats-0.2.20/src/interface/IOffchainAssetReceiptVaultV1.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";
import {StoxAuthorizerInitTest} from "../../../lib/StoxAuthorizerInitTest.sol";

contract StoxOffchainAssetReceiptVaultAuthorizerV1UnknownConfigVersionTest is StoxAuthorizerInitTest {
    address constant ADMIN = address(uint160(uint256(keccak256("ADMIN"))));

    function testV1ConfigIsUnknownVersion(address admin) external {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();
        vm.expectRevert(
            abi.encodeWithSelector(UnknownAuthorizerConfigVersion.selector, bytes32(uint256(uint160(admin))))
        );
        authorizer.initialize(abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: admin})));
    }

    function testWrongTagOverABoundConfigIsUnknownVersion(bytes32 version) external {
        vm.assume(version != OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CONFIG_V2_TAG);
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();
        LibTestDeploy.authorizerData(vm, ADMIN);
        bytes memory data =
            abi.encode(version, LibRegistryAuthority.ROOT_AUTHORITY, LibTestDeploy.AUTHORIZER_INITIAL_ADMIN_NAME);
        vm.expectRevert(abi.encodeWithSelector(UnknownAuthorizerConfigVersion.selector, version));
        authorizer.initialize(data);
    }

    function testVaultConfigIsUnknownVersion() external {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();
        bytes memory data = LibTestDeploy.vaultData(
            "ST0XTEST", LibRegistryAuthority.ROOT_AUTHORITY, LibTestDeploy.AUTHORIZER_INITIAL_ADMIN_NAME
        );
        vm.expectRevert(
            abi.encodeWithSelector(UnknownAuthorizerConfigVersion.selector, OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG)
        );
        authorizer.initialize(data);
    }

    function testDataShorterThanAWordIsUnknownVersionZero(uint256 length) external {
        length = bound(length, 0, 0x1f);
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();
        bytes memory data = prefix(LibTestDeploy.authorizerData(vm, ADMIN), length);
        vm.expectRevert(abi.encodeWithSelector(UnknownAuthorizerConfigVersion.selector, bytes32(0)));
        authorizer.initialize(data);
    }
}
