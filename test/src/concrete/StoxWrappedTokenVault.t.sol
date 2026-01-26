// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {StoxWrappedTokenVault, ICloneableV2, ICLONEABLE_V2_SUCCESS} from "src/concrete/StoxWrappedTokenVault.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract StoxWrappedTokenVaultTest is Test {
    /// Test that the constructor disables initializers.
    function testConstructorDisablesInitializers(address asset) external {
        StoxWrappedTokenVault stoxWrappedTokenVault = new StoxWrappedTokenVault();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        stoxWrappedTokenVault.initialize(abi.encode(asset));
    }

    /// Test that the contract implements ICloneableV2's initialize signature
    /// function.
    function testInitializeSignatureFunction(address asset) external {
        StoxWrappedTokenVault stoxWrappedTokenVault = new StoxWrappedTokenVault();

        vm.expectRevert(abi.encodeWithSelector(ICloneableV2.InitializeSignatureFn.selector));
        stoxWrappedTokenVault.initialize(asset);
    }

    /// Test that the initialize function works as expected.
    function testInitializeFunction(string memory name, string memory symbol) external {
        address asset = makeAddr("asset");
        address alice = makeAddr("alice");
        StoxWrappedTokenVault stoxWrappedTokenVaultImplementation = new StoxWrappedTokenVault();

        UpgradeableBeacon beacon = new UpgradeableBeacon(address(stoxWrappedTokenVaultImplementation), alice);

        StoxWrappedTokenVault stoxWrappedTokenVault =
            StoxWrappedTokenVault(address(new BeaconProxy(address(beacon), "")));

        bytes32 success = stoxWrappedTokenVault.initialize(abi.encode(asset));
        assertEq(success, ICLONEABLE_V2_SUCCESS);

        vm.mockCall(address(asset), abi.encodeWithSelector(IERC20Metadata.name.selector), abi.encode(name));
        vm.mockCall(address(asset), abi.encodeWithSelector(IERC20Metadata.symbol.selector), abi.encode(symbol));
        vm.mockCall(address(asset), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));

        assertEq(address(stoxWrappedTokenVault.asset()), asset);
        assertEq(stoxWrappedTokenVault.name(), string.concat("Wrapped ", IERC20Metadata(asset).name()));
        assertEq(stoxWrappedTokenVault.symbol(), string.concat("w", IERC20Metadata(asset).symbol()));
        assertEq(stoxWrappedTokenVault.decimals(), IERC20Metadata(asset).decimals());
        assertEq(stoxWrappedTokenVault.totalSupply(), 0);
        assertEq(stoxWrappedTokenVault.balanceOf(alice), 0);
        assertEq(stoxWrappedTokenVault.balanceOf(address(this)), 0);
        assertEq(stoxWrappedTokenVault.allowance(address(this), alice), 0);
        assertEq(stoxWrappedTokenVault.allowance(alice, address(this)), 0);

        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(stoxWrappedTokenVault)),
            abi.encode(50)
        );
        assertEq(stoxWrappedTokenVault.totalAssets(), 50);
    }
}
