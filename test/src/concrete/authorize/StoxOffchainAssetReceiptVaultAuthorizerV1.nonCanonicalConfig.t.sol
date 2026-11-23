// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {
    NonCanonicalAuthorizerConfig,
    OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CONFIG_V2_TAG
} from "rain-vats-0.2.20/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";
import {StoxAuthorizerInitTest} from "../../../lib/StoxAuthorizerInitTest.sol";

contract StoxOffchainAssetReceiptVaultAuthorizerV1NonCanonicalConfigTest is StoxAuthorizerInitTest {
    address constant ADMIN = address(uint160(uint256(keccak256("ADMIN"))));

    function testTrailingBytesAreNonCanonical(bytes memory extra) external {
        vm.assume(extra.length > 0);
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();
        bytes memory data = abi.encodePacked(LibTestDeploy.authorizerData(vm, ADMIN), extra);
        vm.expectRevert(abi.encodeWithSelector(NonCanonicalAuthorizerConfig.selector));
        authorizer.initialize(data);
    }

    function testTruncatedConfigIsNonCanonical(uint256 length) external {
        length = bound(length, 0x20, 0x5f);
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();
        bytes memory data = prefix(LibTestDeploy.authorizerData(vm, ADMIN), length);
        vm.expectRevert(abi.encodeWithSelector(NonCanonicalAuthorizerConfig.selector));
        authorizer.initialize(data);
    }

    function testDirtyAuthorityHighBitsAreNonCanonical(uint96 dirty) external {
        vm.assume(dirty != 0);
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();
        LibTestDeploy.authorizerData(vm, ADMIN);
        bytes memory data = abi.encode(
            OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CONFIG_V2_TAG,
            uint256(uint160(LibRegistryAuthority.ROOT_AUTHORITY)) | (uint256(dirty) << 160),
            LibTestDeploy.AUTHORIZER_INITIAL_ADMIN_NAME
        );
        vm.expectRevert(abi.encodeWithSelector(NonCanonicalAuthorizerConfig.selector));
        authorizer.initialize(data);
    }
}
