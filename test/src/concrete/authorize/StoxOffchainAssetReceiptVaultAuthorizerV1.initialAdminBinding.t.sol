// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {
    NonCanonicalInitialAdmin,
    ZeroInitialAdmin,
    INITIAL_ADMIN_VALUE_TYPE_HASH
} from "rain-vats-0.2.20/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";
import {StoxAuthorizerInitTest} from "../../../lib/StoxAuthorizerInitTest.sol";

contract StoxOffchainAssetReceiptVaultAuthorizerV1InitialAdminBindingTest is StoxAuthorizerInitTest {
    address constant ADMIN = address(uint160(uint256(keccak256("ADMIN"))));
    address constant AUTHORITY = LibRegistryAuthority.ROOT_AUTHORITY;
    bytes32 constant NAME = LibTestDeploy.AUTHORIZER_INITIAL_ADMIN_NAME;

    function authorizerOverBinding(string memory valueType, bytes memory value)
        internal
        returns (StoxOffchainAssetReceiptVaultAuthorizerV1, bytes memory)
    {
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bind(vm, AUTHORITY, NAME, valueType, value);
        return (newAuthorizer(), LibTestDeploy.authorizerConfig(AUTHORITY, NAME));
    }

    function testUnboundNameReverts(bytes32 name) external {
        LibTestDeploy.etchConfigRegistry(vm);
        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer = newAuthorizer();
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.NameNotRegistered.selector, AUTHORITY, name));
        authorizer.initialize(LibTestDeploy.authorizerConfig(AUTHORITY, name));
    }

    function testNonAddressValueTypeReverts(string memory valueType) external {
        vm.assume(bytes(valueType).length > 0 && keccak256(bytes(valueType)) != INITIAL_ADMIN_VALUE_TYPE_HASH);
        (StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer, bytes memory data) =
            authorizerOverBinding(valueType, abi.encode(ADMIN));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.ValueTypeMismatch.selector,
                AUTHORITY,
                NAME,
                INITIAL_ADMIN_VALUE_TYPE_HASH,
                keccak256(bytes(valueType))
            )
        );
        authorizer.initialize(data);
    }

    function testValueLongerThanAWordReverts(bytes memory extra) external {
        vm.assume(extra.length > 0);
        (StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer, bytes memory data) =
            authorizerOverBinding("address", abi.encodePacked(abi.encode(ADMIN), extra));
        vm.expectRevert(abi.encodeWithSelector(NonCanonicalInitialAdmin.selector, AUTHORITY, NAME));
        authorizer.initialize(data);
    }

    function testValueShorterThanAWordReverts(bytes32 word, uint256 length) external {
        length = bound(length, 1, 0x1f);
        (StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer, bytes memory data) =
            authorizerOverBinding("address", prefix(abi.encode(word), length));
        vm.expectRevert(abi.encodeWithSelector(NonCanonicalInitialAdmin.selector, AUTHORITY, NAME));
        authorizer.initialize(data);
    }

    function testPackedAddressReverts() external {
        (StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer, bytes memory data) =
            authorizerOverBinding("address", abi.encodePacked(ADMIN));
        vm.expectRevert(abi.encodeWithSelector(NonCanonicalInitialAdmin.selector, AUTHORITY, NAME));
        authorizer.initialize(data);
    }

    function testDirtyAdminHighBitsRevert(uint96 dirty) external {
        vm.assume(dirty != 0);
        (StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer, bytes memory data) =
            authorizerOverBinding("address", abi.encode(uint256(uint160(ADMIN)) | (uint256(dirty) << 160)));
        vm.expectRevert(abi.encodeWithSelector(NonCanonicalInitialAdmin.selector, AUTHORITY, NAME));
        authorizer.initialize(data);
    }

    function testZeroAdminReverts() external {
        (StoxOffchainAssetReceiptVaultAuthorizerV1 authorizer, bytes memory data) =
            authorizerOverBinding("address", abi.encode(address(0)));
        vm.expectRevert(abi.encodeWithSelector(ZeroInitialAdmin.selector));
        authorizer.initialize(data);
    }
}
