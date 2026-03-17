// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {StoxWrappedTokenVault, ZeroAsset} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {ICloneableV2} from "rain.factory/interface/ICloneableV2.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer,
    StoxWrappedTokenVaultBeaconSetDeployerConfig
} from "../../../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {MockERC20} from "../../concrete/MockERC20.sol";

contract StoxWrappedTokenVaultTest is Test {
    function _deployer() internal returns (StoxWrappedTokenVaultBeaconSetDeployer) {
        StoxWrappedTokenVault impl = new StoxWrappedTokenVault();
        return new StoxWrappedTokenVaultBeaconSetDeployer(
            StoxWrappedTokenVaultBeaconSetDeployerConfig({
                initialOwner: address(this),
                initialStoxWrappedTokenVaultImplementation: address(impl)
            })
        );
    }

    /// Constructor disables initializers on the implementation.
    function testConstructorDisablesInitializers() external {
        StoxWrappedTokenVault impl = new StoxWrappedTokenVault();
        vm.expectRevert();
        impl.initialize(abi.encode(address(1)));
    }

    /// initialize(address) must always revert with InitializeSignatureFn.
    function testInitializeAddressAlwaysReverts(address asset) external {
        StoxWrappedTokenVault impl = new StoxWrappedTokenVault();
        vm.expectRevert(abi.encodeWithSelector(ICloneableV2.InitializeSignatureFn.selector));
        impl.initialize(asset);
    }

    /// initialize(bytes) with zero asset reverts via the deployer's
    /// ZeroVaultAsset check.
    function testInitializeZeroAssetViaDeployer() external {
        StoxWrappedTokenVaultBeaconSetDeployer deployer = _deployer();
        vm.expectRevert();
        deployer.newStoxWrappedTokenVault(address(0));
    }

    /// initialize(bytes) with zero asset reverts with ZeroAsset when called
    /// directly on a proxy (bypassing the deployer).
    function testInitializeZeroAssetDirect() external {
        StoxWrappedTokenVaultBeaconSetDeployer deployer = _deployer();
        StoxWrappedTokenVault vault = StoxWrappedTokenVault(
            address(new BeaconProxy(address(deployer.I_STOX_WRAPPED_TOKEN_VAULT_BEACON()), ""))
        );
        vm.expectRevert(abi.encodeWithSelector(ZeroAsset.selector));
        vault.initialize(abi.encode(address(0)));
    }

    /// initialize(bytes) succeeds via beacon proxy with valid asset.
    function testInitializeSuccess() external {
        StoxWrappedTokenVaultBeaconSetDeployer deployer = _deployer();
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = deployer.newStoxWrappedTokenVault(address(asset));
        assertEq(vault.asset(), address(asset));
    }

    /// name() prepends "Wrapped " to the underlying asset name.
    function testNameDelegation() external {
        StoxWrappedTokenVaultBeaconSetDeployer deployer = _deployer();
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = deployer.newStoxWrappedTokenVault(address(asset));
        assertEq(vault.name(), "Wrapped Test Token");
    }

    /// symbol() prepends "w" to the underlying asset symbol.
    function testSymbolDelegation() external {
        StoxWrappedTokenVaultBeaconSetDeployer deployer = _deployer();
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = deployer.newStoxWrappedTokenVault(address(asset));
        assertEq(vault.symbol(), "wTT");
    }
}
