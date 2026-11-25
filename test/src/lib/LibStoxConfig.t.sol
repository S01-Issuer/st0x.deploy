// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.38/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.38/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.38/src/lib/LibConfigRegistryDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.38/src/lib/LibRegistryAuthority.sol";
import {
    INITIAL_ADMIN_VALUE_TYPE_HASH,
    NonCanonicalInitialAdmin
} from "rain-vats-0.2.25/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LibStoxConfigHarness} from "./LibStoxConfigHarness.sol";

contract LibStoxConfigTest is Test {
    LibStoxConfigHarness internal harness;

    function setUp() external {
        harness = new LibStoxConfigHarness();
        LibTestDeploy.etchConfigRegistry(vm);
    }

    function testFuzzBeaconInitialOwnerFollowsBinding(address first, address second) external {
        LibTestDeploy.bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.BEACON_INITIAL_OWNER_NAME,
            "address",
            abi.encode(first)
        );
        assertEq(harness.beaconInitialOwner(), first);
        LibTestDeploy.bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.BEACON_INITIAL_OWNER_NAME,
            "address",
            abi.encode(second)
        );
        assertEq(harness.beaconInitialOwner(), second);
    }

    function testBeaconInitialOwnerUnboundReverts() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxConfig.BEACON_INITIAL_OWNER_NAME
            )
        );
        harness.beaconInitialOwner();
    }

    function testFuzzBeaconInitialOwnerIgnoresOtherAuthority(address authority, address owner) external {
        vm.assume(authority != LibRegistryAuthority.ROOT_AUTHORITY);
        vm.prank(authority);
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV5(authority, LibStoxConfig.BEACON_INITIAL_OWNER_NAME, "address", abi.encode(owner), "");
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxConfig.BEACON_INITIAL_OWNER_NAME
            )
        );
        harness.beaconInitialOwner();
    }

    function testFuzzBeaconInitialOwnerIgnoresOtherName(bytes32 name, address owner) external {
        vm.assume(name != LibStoxConfig.BEACON_INITIAL_OWNER_NAME);
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV5(LibRegistryAuthority.ROOT_AUTHORITY, name, "address", abi.encode(owner), "");
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxConfig.BEACON_INITIAL_OWNER_NAME
            )
        );
        harness.beaconInitialOwner();
    }

    function bindAuthoriserInitialAdmin(string memory valueType, bytes memory value) internal {
        LibTestDeploy.bind(
            vm, LibRegistryAuthority.ROOT_AUTHORITY, LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME, valueType, value
        );
    }

    function expectNonCanonicalAuthoriserInitialAdmin() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                NonCanonicalInitialAdmin.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME
            )
        );
    }

    function testFuzzAuthoriserInitialAdminFollowsBinding(address first, address second) external {
        bindAuthoriserInitialAdmin("address", abi.encode(first));
        assertEq(harness.authoriserInitialAdmin(), first);
        bindAuthoriserInitialAdmin("address", abi.encode(second));
        assertEq(harness.authoriserInitialAdmin(), second);
    }

    function testAuthoriserInitialAdminUnboundReverts() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME
            )
        );
        harness.authoriserInitialAdmin();
    }

    function testFuzzAuthoriserInitialAdminRefusesNonAddressValueType(string memory valueType, address admin)
        external
    {
        vm.assume(bytes(valueType).length > 0 && keccak256(bytes(valueType)) != INITIAL_ADMIN_VALUE_TYPE_HASH);
        bindAuthoriserInitialAdmin(valueType, abi.encode(admin));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.ValueTypeMismatch.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME,
                INITIAL_ADMIN_VALUE_TYPE_HASH,
                keccak256(bytes(valueType))
            )
        );
        harness.authoriserInitialAdmin();
    }

    function testFuzzAuthoriserInitialAdminRefusesTrailingBytes(address admin, bytes memory extra) external {
        vm.assume(extra.length > 0);
        bindAuthoriserInitialAdmin("address", abi.encodePacked(abi.encode(admin), extra));
        expectNonCanonicalAuthoriserInitialAdmin();
        harness.authoriserInitialAdmin();
    }

    function testFuzzAuthoriserInitialAdminRefusesShortValue(bytes32 word, uint256 length) external {
        length = bound(length, 1, 0x1f);
        bytes memory value = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            value[i] = word[i];
        }
        bindAuthoriserInitialAdmin("address", value);
        expectNonCanonicalAuthoriserInitialAdmin();
        harness.authoriserInitialAdmin();
    }

    function testFuzzAuthoriserInitialAdminRefusesDirtyUpperBits(address admin, uint96 dirty) external {
        vm.assume(dirty != 0);
        bindAuthoriserInitialAdmin("address", abi.encode(uint256(uint160(admin)) | (uint256(dirty) << 160)));
        expectNonCanonicalAuthoriserInitialAdmin();
        harness.authoriserInitialAdmin();
    }
}
