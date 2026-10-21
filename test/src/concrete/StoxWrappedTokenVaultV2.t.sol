// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {StoxWrappedTokenVault, ZeroAsset} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {MockERC20} from "../../concrete/MockERC20.sol";

/// @title StoxWrappedTokenVaultV2Test
/// @notice Tests V2-specific behaviour changes that differ from V1.
contract StoxWrappedTokenVaultV2Test is Test {
    /// V2 StoxWrappedTokenVault reverts with ZeroAsset when initialized with
    /// address(0). This is the fix for the V1 vulnerability.
    function testV2ZeroAssetReverts() external {
        LibTestDeploy.deployAll(vm);
        vm.expectRevert(abi.encodeWithSelector(ZeroAsset.selector));
        LibTestDeploy.newWrapper(address(0));
    }

    /// A factory-deployed V2 wrapper carries the correct asset.
    function testV2NewVaultSuccess() external {
        LibTestDeploy.deployAll(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = LibTestDeploy.newWrapper(address(asset));

        assertEq(vault.asset(), address(asset));
        assertEq(vault.name(), "Wrapped Test Token");
        assertEq(vault.symbol(), "wTT");
    }
}
