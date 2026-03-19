// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {StoxAuthorizer} from "../../../../src/concrete/authorize/StoxAuthorizer.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "ethgild/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {Unauthorized} from "ethgild/interface/IAuthorizeV1.sol";
import {UPDATE_NAME_SYMBOL, UPDATE_NAME_SYMBOL_ADMIN} from "../../../../src/concrete/CorporateActionRegistry.sol";

contract StoxAuthorizerTest is Test {
    StoxAuthorizer internal authorizer;
    address internal admin;

    function setUp() public {
        admin = makeAddr("admin");
        StoxAuthorizer impl = new StoxAuthorizer();
        authorizer = StoxAuthorizer(Clones.clone(address(impl)));
        authorizer.initialize(abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: admin})));
    }

    /// Initial admin receives the UPDATE_NAME_SYMBOL_ADMIN role.
    function testInitialAdminHasUpdateNameSymbolAdmin() external view {
        assertTrue(authorizer.hasRole(UPDATE_NAME_SYMBOL_ADMIN, admin));
    }

    /// Initial admin does NOT automatically get UPDATE_NAME_SYMBOL — only the
    /// admin role. They must explicitly grant UPDATE_NAME_SYMBOL to themselves
    /// or to the registry.
    function testInitialAdminDoesNotHaveUpdateNameSymbol() external view {
        assertFalse(authorizer.hasRole(UPDATE_NAME_SYMBOL, admin));
    }

    /// Admin can grant UPDATE_NAME_SYMBOL to an address.
    function testAdminCanGrantUpdateNameSymbol() external {
        address registry = makeAddr("registry");
        vm.prank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, registry);
        assertTrue(authorizer.hasRole(UPDATE_NAME_SYMBOL, registry));
    }

    /// Non-admin cannot grant UPDATE_NAME_SYMBOL.
    function testNonAdminCannotGrantUpdateNameSymbol() external {
        address rando = makeAddr("rando");
        address registry = makeAddr("registry");
        vm.prank(rando);
        vm.expectRevert();
        authorizer.grantRole(UPDATE_NAME_SYMBOL, registry);
    }

    /// authorize succeeds for a user with UPDATE_NAME_SYMBOL role.
    function testAuthorizeSucceedsWithRole() external {
        address registry = makeAddr("registry");
        vm.prank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, registry);

        // Should not revert.
        authorizer.authorize(registry, UPDATE_NAME_SYMBOL, abi.encode("NewName", "NEW"));
    }

    /// authorize reverts for a user without UPDATE_NAME_SYMBOL role.
    function testAuthorizeRevertsWithoutRole() external {
        address rando = makeAddr("rando");
        vm.expectRevert(
            abi.encodeWithSelector(Unauthorized.selector, rando, UPDATE_NAME_SYMBOL, abi.encode("NewName", "NEW"))
        );
        authorizer.authorize(rando, UPDATE_NAME_SYMBOL, abi.encode("NewName", "NEW"));
    }

    /// Admin can revoke UPDATE_NAME_SYMBOL.
    function testAdminCanRevokeUpdateNameSymbol() external {
        address registry = makeAddr("registry");
        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, registry);
        assertTrue(authorizer.hasRole(UPDATE_NAME_SYMBOL, registry));

        authorizer.revokeRole(UPDATE_NAME_SYMBOL, registry);
        assertFalse(authorizer.hasRole(UPDATE_NAME_SYMBOL, registry));
        vm.stopPrank();

        // authorize should now revert.
        vm.expectRevert(
            abi.encodeWithSelector(Unauthorized.selector, registry, UPDATE_NAME_SYMBOL, abi.encode("X", "X"))
        );
        authorizer.authorize(registry, UPDATE_NAME_SYMBOL, abi.encode("X", "X"));
    }

    /// UPDATE_NAME_SYMBOL_ADMIN is self-administering — the admin role for
    /// UPDATE_NAME_SYMBOL_ADMIN is UPDATE_NAME_SYMBOL_ADMIN itself.
    function testUpdateNameSymbolAdminIsSelfAdministering() external view {
        assertEq(authorizer.getRoleAdmin(UPDATE_NAME_SYMBOL_ADMIN), UPDATE_NAME_SYMBOL_ADMIN);
    }

    /// UPDATE_NAME_SYMBOL's admin role is UPDATE_NAME_SYMBOL_ADMIN.
    function testUpdateNameSymbolAdminRole() external view {
        assertEq(authorizer.getRoleAdmin(UPDATE_NAME_SYMBOL), UPDATE_NAME_SYMBOL_ADMIN);
    }

    /// Admin can delegate the admin role to another address.
    function testAdminCanDelegateAdminRole() external {
        address newAdmin = makeAddr("newAdmin");
        vm.prank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL_ADMIN, newAdmin);
        assertTrue(authorizer.hasRole(UPDATE_NAME_SYMBOL_ADMIN, newAdmin));

        // New admin can now grant UPDATE_NAME_SYMBOL.
        address registry = makeAddr("registry");
        vm.prank(newAdmin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, registry);
        assertTrue(authorizer.hasRole(UPDATE_NAME_SYMBOL, registry));
    }

    /// Cannot initialize twice.
    function testCannotInitializeTwice() external {
        vm.expectRevert();
        authorizer.initialize(abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: admin})));
    }

    /// Fuzz: authorize always reverts for random addresses without the role.
    function testFuzzAuthorizeRevertsWithoutRole(address user, bytes memory data) external {
        vm.assume(!authorizer.hasRole(UPDATE_NAME_SYMBOL, user));
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, user, UPDATE_NAME_SYMBOL, data));
        authorizer.authorize(user, UPDATE_NAME_SYMBOL, data);
    }
}
