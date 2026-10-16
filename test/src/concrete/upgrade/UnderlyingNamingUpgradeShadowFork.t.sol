// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin-contracts-5.7.0/interfaces/IERC4626.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.5/src/interface/IReceiptVaultV3.sol";
import {IReceiptV3} from "rain-vats-0.2.5/src/interface/IReceiptV3.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";

import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployCurrent} from "../../../../src/generated/LibProdDeployCurrent.sol";
import {LibTokenInvariants} from "../../../../src/lib/LibTokenInvariants.sol";
import {IStoxUnderlyingV1} from "../../../../src/interface/IStoxUnderlyingV1.sol";

/// @title UnderlyingNamingUpgradeShadowForkTest
/// @notice Applies the current receipt vault, corporate-actions facet and
/// wrapped token vault implementations to LIVE Base tokens on a fork, in the
/// order the rollout runs them, and checks that each step leaves token state
/// intact and only moves the metadata once the underlying is set.
///
/// @dev Implementations are planted at their deterministic candidate addresses
/// with `deployCodeTo`, so constructors (the facet's `_SELF`) run in place, and
/// each beacon is upgraded by its live owner.
contract UnderlyingNamingUpgradeShadowForkTest is Test {
    IERC20Metadata internal constant VAULT = IERC20Metadata(LibTokenInvariants.NVDA_RECEIPT_VAULT);
    IERC4626 internal constant WRAPPER = IERC4626(LibTokenInvariants.NVDA_WRAPPED_TOKEN_VAULT);

    string internal vaultNameBefore;
    string internal vaultSymbolBefore;
    string internal wrapperNameBefore;
    string internal wrapperSymbolBefore;
    string internal receiptNameBefore;
    string internal receiptSymbolBefore;
    uint256 internal vaultSupplyBefore;
    uint256 internal wrapperSupplyBefore;
    uint256 internal wrapperAssetsBefore;

    function setUp() public {
        vm.createSelectFork(LibRainDeploy.BASE);

        vaultNameBefore = VAULT.name();
        vaultSymbolBefore = VAULT.symbol();
        wrapperNameBefore = WRAPPER.name();
        wrapperSymbolBefore = WRAPPER.symbol();
        IReceiptV3 receipt = receiptOf();
        receiptNameBefore = receipt.name();
        receiptSymbolBefore = receipt.symbol();
        vaultSupplyBefore = VAULT.totalSupply();
        wrapperSupplyBefore = WRAPPER.totalSupply();
        wrapperAssetsBefore = WRAPPER.totalAssets();

        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            LibProdDeployCurrent.STOX_CORPORATE_ACTIONS_FACET
        );
        deployCodeTo("src/concrete/StoxReceiptVault.sol:StoxReceiptVault", LibProdDeployCurrent.STOX_RECEIPT_VAULT);
        deployCodeTo(
            "src/concrete/StoxWrappedTokenVault.sol:StoxWrappedTokenVault",
            LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT
        );
    }

    function receiptOf() internal view returns (IReceiptV3) {
        return IReceiptV3(address(IReceiptVaultV3(payable(address(VAULT))).receipt()));
    }

    function upgrade(address beacon, address implementation) internal {
        vm.prank(Ownable(beacon).owner());
        UpgradeableBeacon(beacon).upgradeTo(implementation);
    }

    function upgradeWrapper() internal {
        upgrade(LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1, LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT);
    }

    function upgradeVault() internal {
        upgrade(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1, LibProdDeployCurrent.STOX_RECEIPT_VAULT);
    }

    function setNvda() internal {
        vm.prank(OwnableUpgradeable(address(VAULT)).owner());
        IStoxUnderlyingV1(address(VAULT)).setUnderlying("NVDA", "NVIDIA Corporation");
    }

    function assertSupplyIntact() internal view {
        assertEq(VAULT.totalSupply(), vaultSupplyBefore, "vault supply moved");
        assertEq(WRAPPER.totalSupply(), wrapperSupplyBefore, "wrapper supply moved");
        assertEq(WRAPPER.totalAssets(), wrapperAssetsBefore, "wrapper assets moved");
    }

    /// The live pair reports the initialized metadata, which the wrapper
    /// derives as "Wrapped " / "w".
    function testLiveBaseline() external view {
        assertEq(vaultSymbolBefore, "tNVDA");
        assertEq(wrapperSymbolBefore, "wtNVDA");
        assertEq(wrapperNameBefore, string.concat("Wrapped ", vaultNameBefore));
    }

    /// A wrapper upgraded ahead of the vault reads no underlying from the
    /// live vault and keeps its current name and symbol.
    function testWrapperUpgradeAloneKeepsMetadata() external {
        upgradeWrapper();
        assertEq(WRAPPER.symbol(), wrapperSymbolBefore);
        assertEq(WRAPPER.name(), wrapperNameBefore);
        assertSupplyIntact();
    }

    /// A vault upgraded with nothing set keeps every token's metadata and
    /// supply, and the facet reads the underlying as unset.
    function testVaultUpgradeUnsetKeepsMetadata() external {
        upgradeVault();
        assertEq(IStoxUnderlyingV1(address(VAULT)).underlyingSymbol(), "");
        assertEq(VAULT.symbol(), vaultSymbolBefore);
        assertEq(VAULT.name(), vaultNameBefore);
        assertEq(WRAPPER.symbol(), wrapperSymbolBefore);
        assertEq(WRAPPER.name(), wrapperNameBefore);
        assertEq(receiptOf().symbol(), receiptSymbolBefore);
        assertEq(receiptOf().name(), receiptNameBefore);
        assertSupplyIntact();
    }

    /// The full rollout: vault upgrade, then setUnderlying by the vault owner,
    /// then the wrapper upgrade.
    function testFullRolloutRenames() external {
        upgradeVault();
        setNvda();
        assertEq(VAULT.symbol(), "tNVDA");
        assertEq(VAULT.name(), "NVIDIA Corporation (ST0x)");
        // The live wrapper implementation still derives from the vault.
        assertEq(WRAPPER.symbol(), "wtNVDA");
        assertEq(WRAPPER.name(), "Wrapped NVIDIA Corporation (ST0x)");

        upgradeWrapper();
        assertEq(WRAPPER.symbol(), "NVDAs");
        assertEq(WRAPPER.name(), "NVIDIA Corporation (ST0x)");
        assertEq(receiptOf().symbol(), receiptSymbolBefore);
        assertSupplyIntact();
    }

    /// Only the vault owner sets the underlying on a live vault.
    function testLiveNonOwnerCannotSet(address caller) external {
        upgradeVault();
        vm.assume(caller != OwnableUpgradeable(address(VAULT)).owner());
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        IStoxUnderlyingV1(address(VAULT)).setUnderlying("NVDA", "NVIDIA Corporation");
    }
}
