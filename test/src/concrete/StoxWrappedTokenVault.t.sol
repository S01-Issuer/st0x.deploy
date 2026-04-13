// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {StoxWrappedTokenVault, ZeroAsset} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {ICloneableV2, ICLONEABLE_V2_SUCCESS} from "rain.factory/interface/ICloneableV2.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer,
    ZeroVaultAsset
} from "../../../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {LibProdDeployV3} from "../../../src/lib/LibProdDeployV3.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {MockERC20} from "../../concrete/MockERC20.sol";

contract StoxWrappedTokenVaultTest is Test {
    /// Constructor disables initializers on the implementation.
    function testConstructorDisablesInitializers() external {
        StoxWrappedTokenVault impl = new StoxWrappedTokenVault();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
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
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        vm.expectRevert(abi.encodeWithSelector(ZeroVaultAsset.selector));
        StoxWrappedTokenVaultBeaconSetDeployer(LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER)
            .newStoxWrappedTokenVault(address(0));
    }

    /// initialize(bytes) with zero asset reverts with ZeroAsset when called
    /// directly on a proxy (bypassing the deployer).
    function testInitializeZeroAssetDirect() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        StoxWrappedTokenVault vault =
            StoxWrappedTokenVault(address(new BeaconProxy(LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON, "")));
        vm.expectRevert(abi.encodeWithSelector(ZeroAsset.selector));
        vault.initialize(abi.encode(address(0)));
    }

    /// initialize(bytes) succeeds via beacon proxy with valid asset.
    function testInitializeSuccess() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));
        assertEq(vault.asset(), address(asset));
    }

    /// initialize(bytes) returns ICLONEABLE_V2_SUCCESS on a fresh proxy.
    function testInitializeReturnsCloneableV2Success() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault =
            StoxWrappedTokenVault(address(new BeaconProxy(LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON, "")));
        bytes32 result = vault.initialize(abi.encode(address(asset)));
        assertEq(result, ICLONEABLE_V2_SUCCESS);
    }

    /// initialize(bytes) emits StoxWrappedTokenVaultInitialized with sender and asset.
    function testInitializeEmitsEvent() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault =
            StoxWrappedTokenVault(address(new BeaconProxy(LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON, "")));
        vm.expectEmit(true, true, false, false, address(vault));
        emit StoxWrappedTokenVault.StoxWrappedTokenVaultInitialized(address(this), address(asset));
        vault.initialize(abi.encode(address(asset)));
    }

    /// Double initialization reverts with InvalidInitialization.
    function testDoubleInitializeReverts() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault =
            StoxWrappedTokenVault(address(new BeaconProxy(LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON, "")));
        vault.initialize(abi.encode(address(asset)));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(abi.encode(address(asset)));
    }

    /// name() prepends "Wrapped " to the underlying asset name.
    function testNameDelegation() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));
        assertEq(vault.name(), "Wrapped Test Token");
    }

    /// symbol() prepends "w" to the underlying asset symbol.
    function testSymbolDelegation() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));
        assertEq(vault.symbol(), "wTT");
    }

    /// totalAssets() returns zero for a freshly-initialized vault.
    function testTotalAssetsInitiallyZero() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));
        assertEq(vault.totalAssets(), 0);
    }

    /// deposit() transfers assets and mints shares 1:1 (OZ default, initial deposit).
    function testDepositMintSharesOneToOne(uint256 amount) external {
        amount = bound(amount, 1, type(uint128).max);
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));

        address alice = address(0xA11CE);
        asset.mint(alice, amount);

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, alice);
        vm.stopPrank();

        assertEq(shares, amount, "shares should equal assets deposited (1:1 initial rate)");
        assertEq(vault.balanceOf(alice), amount, "alice share balance should equal deposited amount");
        assertEq(vault.totalAssets(), amount, "totalAssets should equal deposited amount");
    }

    /// withdraw() returns assets and burns shares round-trip.
    function testWithdrawRoundTrip(uint256 amount) external {
        amount = bound(amount, 1, type(uint128).max);
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));

        address alice = address(0xA11CE);
        asset.mint(alice, amount);

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        vault.deposit(amount, alice);

        uint256 assetBalanceBefore = asset.balanceOf(alice);
        vault.withdraw(amount, alice, alice);
        vm.stopPrank();

        assertEq(asset.balanceOf(alice), assetBalanceBefore + amount, "alice should recover all assets");
        assertEq(vault.balanceOf(alice), 0, "alice shares should be zero after full withdrawal");
        assertEq(vault.totalAssets(), 0, "vault should have no assets after full withdrawal");
    }

    /// convertToShares / convertToAssets round-trip at 1:1 rate.
    function testConvertRoundTrip(uint256 amount) external {
        amount = bound(amount, 1, type(uint128).max);
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));

        uint256 shares = vault.convertToShares(amount);
        uint256 assets = vault.convertToAssets(shares);
        assertEq(assets, amount, "convertToAssets(convertToShares(x)) should equal x at 1:1 rate");
    }

    /// previewDeposit agrees with actual deposit shares minted.
    function testPreviewDepositMatchesActual(uint256 amount) external {
        amount = bound(amount, 1, type(uint128).max);
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));

        uint256 expectedShares = vault.previewDeposit(amount);

        address alice = address(0xA11CE);
        asset.mint(alice, amount);

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        uint256 actualShares = vault.deposit(amount, alice);
        vm.stopPrank();

        assertEq(actualShares, expectedShares, "previewDeposit must match actual deposit");
    }

    /// previewWithdraw agrees with actual shares burned on withdraw.
    function testPreviewWithdrawMatchesActual(uint256 amount) external {
        amount = bound(amount, 1, type(uint128).max);
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));

        address alice = address(0xA11CE);
        asset.mint(alice, amount);

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        vault.deposit(amount, alice);
        vm.stopPrank();

        uint256 expectedShares = vault.previewWithdraw(amount);

        vm.prank(alice);
        uint256 actualShares = vault.withdraw(amount, alice, alice);

        assertEq(actualShares, expectedShares, "previewWithdraw must match actual withdraw");
    }

    /// maxDeposit returns type(uint256).max for any receiver (OZ default).
    function testMaxDepositUnbounded(address receiver) external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));
        assertEq(vault.maxDeposit(receiver), type(uint256).max);
    }

    /// maxMint returns type(uint256).max for any receiver (OZ default).
    function testMaxMintUnbounded(address receiver) external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));
        assertEq(vault.maxMint(receiver), type(uint256).max);
    }

    /// maxWithdraw returns the caller's full asset balance after deposit.
    function testMaxWithdrawMatchesDeposit(uint256 amount) external {
        amount = bound(amount, 1, type(uint128).max);
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));

        address alice = address(0xA11CE);
        asset.mint(alice, amount);

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        vault.deposit(amount, alice);
        vm.stopPrank();

        assertEq(vault.maxWithdraw(alice), amount, "maxWithdraw should equal deposited amount");
        assertEq(vault.maxWithdraw(address(0xBEEF)), 0, "maxWithdraw should be zero for non-depositor");
    }

    /// maxRedeem returns the caller's full share balance after deposit.
    function testMaxRedeemMatchesShares(uint256 amount) external {
        amount = bound(amount, 1, type(uint128).max);
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));

        address alice = address(0xA11CE);
        asset.mint(alice, amount);

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, alice);
        vm.stopPrank();

        assertEq(vault.maxRedeem(alice), shares, "maxRedeem should equal share balance");
        assertEq(vault.maxRedeem(address(0xBEEF)), 0, "maxRedeem should be zero for non-depositor");
    }

    /// mint() mints specific shares and transfers correct assets.
    function testMintShares(uint256 shares) external {
        shares = bound(shares, 1, type(uint128).max);
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));

        address alice = address(0xA11CE);
        uint256 assetsNeeded = vault.previewMint(shares);
        asset.mint(alice, assetsNeeded);

        vm.startPrank(alice);
        asset.approve(address(vault), assetsNeeded);
        uint256 assetsUsed = vault.mint(shares, alice);
        vm.stopPrank();

        assertEq(assetsUsed, assetsNeeded, "mint must consume exactly previewMint assets");
        assertEq(vault.balanceOf(alice), shares, "alice share balance must equal minted shares");
    }

    /// previewRedeem agrees with actual assets returned on redeem.
    function testPreviewRedeemMatchesActual(uint256 amount) external {
        amount = bound(amount, 1, type(uint128).max);
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));

        address alice = address(0xA11CE);
        asset.mint(alice, amount);

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, alice);
        vm.stopPrank();

        uint256 expectedAssets = vault.previewRedeem(shares);

        vm.prank(alice);
        uint256 actualAssets = vault.redeem(shares, alice, alice);

        assertEq(actualAssets, expectedAssets, "previewRedeem must match actual redeem");
    }

    /// redeem() burns shares and returns correct assets.
    function testRedeemShares(uint256 amount) external {
        amount = bound(amount, 1, type(uint128).max);
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));

        address alice = address(0xA11CE);
        asset.mint(alice, amount);

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, alice);

        uint256 assetBalanceBefore = asset.balanceOf(alice);
        uint256 assetsReturned = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        assertEq(assetsReturned, amount, "redeem must return all deposited assets");
        assertEq(asset.balanceOf(alice), assetBalanceBefore + amount, "alice should receive all assets back");
        assertEq(vault.balanceOf(alice), 0, "alice shares must be zero after full redeem");
    }

    /// Direct asset transfer to the vault increases share price — shares are
    /// now worth more assets than originally deposited. This is the vault's
    /// core mechanism for capturing rebases/dividends in price.
    function testSharePriceIncreasesAfterDirectTransfer(uint256 deposit, uint256 bonus) external {
        deposit = bound(deposit, 1e18, type(uint128).max);
        // Bonus must be large enough relative to deposit to survive ERC4626
        // rounding (virtual offset of 1 share + 1 asset).
        bonus = bound(bonus, deposit / 100 + 1, deposit);
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            ).newStoxWrappedTokenVault(address(asset));

        address alice = address(0xA11CE);
        asset.mint(alice, deposit);

        vm.startPrank(alice);
        asset.approve(address(vault), deposit);
        uint256 shares = vault.deposit(deposit, alice);
        vm.stopPrank();

        uint256 preBonus = vault.convertToAssets(shares);

        // Simulate rebase/dividend by transferring bonus assets directly.
        asset.mint(address(vault), bonus);

        // After bonus: totalAssets increases and shares are worth more.
        assertEq(vault.totalAssets(), deposit + bonus, "totalAssets should include bonus");
        assertGt(vault.convertToAssets(shares), preBonus, "post-bonus: shares should be worth more");
    }
}
