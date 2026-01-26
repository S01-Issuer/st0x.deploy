// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {StoxWrappedTokenVault, ICloneableV2} from "src/concrete/StoxWrappedTokenVault.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

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
}
