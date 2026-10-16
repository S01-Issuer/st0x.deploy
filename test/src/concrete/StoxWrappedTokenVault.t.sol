// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {StoxWrappedTokenVault, ZeroAsset} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {ICloneableV2, ICLONEABLE_V2_SUCCESS} from "rain-factory-0.1.30/src/interface/ICloneableV2.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.7.0/proxy/beacon/BeaconProxy.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer,
    ZeroVaultAsset
} from "../../../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.7.0/proxy/utils/Initializable.sol";
import {MockERC20} from "../../concrete/MockERC20.sol";
import {MockUnderlyingERC20} from "../../concrete/MockUnderlyingERC20.sol";
import {RevertingUnderlyingERC20} from "../../concrete/RevertingUnderlyingERC20.sol";
import {RawReturnERC20} from "../../concrete/RawReturnERC20.sol";
import {ST0X_NAME_SUFFIX} from "../../../src/lib/LibUnderlying.sol";

/// @dev "NVDA" left-aligned in a word, as ABI-encoded string data.
bytes32 constant NVDA_WORD = 0x4e56444100000000000000000000000000000000000000000000000000000000;

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
        StoxWrappedTokenVaultBeaconSetDeployer(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE)
            .newStoxWrappedTokenVault(address(0));
    }

    /// initialize(bytes) with zero asset reverts with ZeroAsset when called
    /// directly on a proxy (bypassing the deployer).
    function testInitializeZeroAssetDirect() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        StoxWrappedTokenVault vault = StoxWrappedTokenVault(
            address(new BeaconProxy(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE, ""))
        );
        vm.expectRevert(abi.encodeWithSelector(ZeroAsset.selector));
        vault.initialize(abi.encode(address(0)));
    }

    /// initialize(bytes) succeeds via beacon proxy with valid asset.
    function testInitializeSuccess() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
            ).newStoxWrappedTokenVault(address(asset));
        assertEq(vault.asset(), address(asset));
    }

    /// initialize(bytes) returns ICLONEABLE_V2_SUCCESS on a fresh proxy.
    function testInitializeReturnsCloneableV2Success() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVault(
            address(new BeaconProxy(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE, ""))
        );
        bytes32 result = vault.initialize(abi.encode(address(asset)));
        assertEq(result, ICLONEABLE_V2_SUCCESS);
    }

    /// initialize(bytes) emits StoxWrappedTokenVaultInitialized with sender and asset.
    function testInitializeEmitsEvent() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVault(
            address(new BeaconProxy(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE, ""))
        );
        vm.expectEmit(true, true, false, false, address(vault));
        emit StoxWrappedTokenVault.StoxWrappedTokenVaultInitialized(address(this), address(asset));
        vault.initialize(abi.encode(address(asset)));
    }

    /// Double initialization reverts with InvalidInitialization.
    function testDoubleInitializeReverts() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVault(
            address(new BeaconProxy(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE, ""))
        );
        vault.initialize(abi.encode(address(asset)));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(abi.encode(address(asset)));
    }

    function newWrapper(address asset) internal returns (StoxWrappedTokenVault) {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        return StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
            ).newStoxWrappedTokenVault(asset);
    }

    /// With the underlying set on the asset, symbol() is ticker + "s" and
    /// name() is the underlying name + " (ST0x)".
    function testNameAndSymbolFromUnderlying() external {
        MockUnderlyingERC20 asset = new MockUnderlyingERC20();
        asset.setUnderlyingValues("NVDA", "NVIDIA Corporation");
        StoxWrappedTokenVault vault = newWrapper(address(asset));
        assertEq(vault.symbol(), "NVDAs");
        assertEq(vault.name(), "NVIDIA Corporation (ST0x)");
    }

    /// The derivation holds for any non-empty values and tracks changes on
    /// the asset without any action on the wrapper.
    function testNameAndSymbolFromUnderlyingFuzz(string memory newSymbol, string memory newName) external {
        vm.assume(bytes(newSymbol).length > 0 && bytes(newName).length > 0);
        MockUnderlyingERC20 asset = new MockUnderlyingERC20();
        StoxWrappedTokenVault vault = newWrapper(address(asset));
        asset.setUnderlyingValues(newSymbol, newName);
        assertEq(vault.symbol(), string.concat(newSymbol, "s"));
        assertEq(vault.name(), string.concat(newName, ST0X_NAME_SUFFIX));
    }

    /// Empty underlying values fall back to the asset's ERC-20 metadata,
    /// each independently of the other.
    function testEmptyUnderlyingFallsBack() external {
        MockUnderlyingERC20 asset = new MockUnderlyingERC20();
        StoxWrappedTokenVault vault = newWrapper(address(asset));
        assertEq(vault.symbol(), "wTT");
        assertEq(vault.name(), "Wrapped Test Token");

        asset.setUnderlyingValues("NVDA", "");
        assertEq(vault.symbol(), "NVDAs");
        assertEq(vault.name(), "Wrapped Test Token");

        asset.setUnderlyingValues("", "NVIDIA Corporation");
        assertEq(vault.symbol(), "wTT");
        assertEq(vault.name(), "NVIDIA Corporation (ST0x)");
    }

    /// Reverting underlying getters fall back rather than reverting.
    function testRevertingUnderlyingFallsBack() external {
        StoxWrappedTokenVault vault = newWrapper(address(new RevertingUnderlyingERC20()));
        assertEq(vault.symbol(), "wTT");
        assertEq(vault.name(), "Wrapped Test Token");
    }

    /// A reverting call falls back even when its revert data is a
    /// well-formed ABI string.
    function testRevertWithStringDataFallsBack() external {
        RawReturnERC20 asset = new RawReturnERC20();
        asset.setRaw(abi.encode("NVDA"));
        asset.setRevert(true);
        StoxWrappedTokenVault vault = newWrapper(address(asset));
        assertEq(vault.symbol(), "wTT");
        assertEq(vault.name(), "Wrapped Test Token");
    }

    /// A successful call returning no data falls back.
    function testEmptyReturnDataFallsBack() external {
        RawReturnERC20 asset = new RawReturnERC20();
        StoxWrappedTokenVault vault = newWrapper(address(asset));
        assertEq(vault.symbol(), "wTT");
        assertEq(vault.name(), "Wrapped Test Token");
    }

    /// Return data too short to hold an ABI string falls back.
    function testShortReturnDataFallsBack() external {
        RawReturnERC20 asset = new RawReturnERC20();
        asset.setRaw(abi.encode(uint256(0x20)));
        StoxWrappedTokenVault vault = newWrapper(address(asset));
        assertEq(vault.symbol(), "wTT");
    }

    /// A string offset other than 0x20 falls back.
    function testBadOffsetFallsBack() external {
        RawReturnERC20 asset = new RawReturnERC20();
        asset.setRaw(abi.encode(uint256(0x40), uint256(4), NVDA_WORD));
        StoxWrappedTokenVault vault = newWrapper(address(asset));
        assertEq(vault.symbol(), "wTT");
    }

    /// A string length running past the return data falls back.
    function testOverlongLengthFallsBack(uint256 length) external {
        length = bound(length, 33, type(uint256).max);
        RawReturnERC20 asset = new RawReturnERC20();
        asset.setRaw(abi.encode(uint256(0x20), length, NVDA_WORD));
        StoxWrappedTokenVault vault = newWrapper(address(asset));
        assertEq(vault.symbol(), "wTT");
        assertEq(vault.name(), "Wrapped Test Token");
    }

    /// A string exactly filling the return data after its head is accepted.
    function testStringFillingReturnDataDecodes() external {
        string memory full = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";
        RawReturnERC20 asset = new RawReturnERC20();
        bytes memory raw = abi.encode(full);
        assertEq(raw.length, 0x60);
        asset.setRaw(raw);
        StoxWrappedTokenVault vault = newWrapper(address(asset));
        assertEq(vault.symbol(), string.concat(full, "s"));
    }

    /// Well-formed raw return data from an arbitrary contract is decoded.
    function testWellFormedRawReturnDataDecodes() external {
        RawReturnERC20 asset = new RawReturnERC20();
        asset.setRaw(abi.encode("NVDA"));
        StoxWrappedTokenVault vault = newWrapper(address(asset));
        assertEq(vault.symbol(), "NVDAs");
        assertEq(vault.name(), "NVDA (ST0x)");
    }

    /// Over a plain ERC-20 with no underlying getters, name() falls back to
    /// "Wrapped " + the asset name.
    function testNameDelegation() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
            ).newStoxWrappedTokenVault(address(asset));
        assertEq(vault.name(), "Wrapped Test Token");
    }

    /// Over a plain ERC-20 with no underlying getters, symbol() falls back to
    /// "w" + the asset symbol.
    function testSymbolDelegation() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
            ).newStoxWrappedTokenVault(address(asset));
        assertEq(vault.symbol(), "wTT");
    }

    /// totalAssets() returns zero for a freshly-initialized vault.
    function testTotalAssetsInitiallyZero() external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
            ).newStoxWrappedTokenVault(address(asset));
        assertEq(vault.totalAssets(), 0);
    }

    /// deposit() transfers assets and mints shares 1:1 (OZ default, initial deposit).
    function testDepositMintSharesOneToOne(uint256 amount) external {
        amount = bound(amount, 1, type(uint128).max);
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
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
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
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
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
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
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
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
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
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
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
            ).newStoxWrappedTokenVault(address(asset));
        assertEq(vault.maxDeposit(receiver), type(uint256).max);
    }

    /// maxMint returns type(uint256).max for any receiver (OZ default).
    function testMaxMintUnbounded(address receiver) external {
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
            ).newStoxWrappedTokenVault(address(asset));
        assertEq(vault.maxMint(receiver), type(uint256).max);
    }

    /// maxWithdraw returns the caller's full asset balance after deposit.
    function testMaxWithdrawMatchesDeposit(uint256 amount) external {
        amount = bound(amount, 1, type(uint128).max);
        LibTestDeploy.deployWrappedTokenVaultBeaconSet(vm);
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault vault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
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
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
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
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
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
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
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
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
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
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CANDIDATE
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
