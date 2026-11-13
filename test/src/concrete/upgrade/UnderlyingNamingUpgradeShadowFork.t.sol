// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin-contracts-5.7.0/interfaces/IERC4626.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.20/src/interface/IReceiptVaultV3.sol";
import {IReceiptV3} from "rain-vats-0.2.20/src/interface/IReceiptV3.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployCurrent} from "../../../../src/generated/LibProdDeployCurrent.sol";
import {LibTokenInvariants} from "../../../../src/lib/LibTokenInvariants.sol";
import {IStoxUnderlyingV2} from "../../../../src/interface/IStoxUnderlyingV2.sol";
import {ICorporateActionsV1} from "../../../../src/interface/ICorporateActionsV1.sol";
import {CorporateActionsFacetNotDeployed} from "../../../../src/error/ErrCorporateAction.sol";
import {MalformedUnderlyingSnapshot} from "../../../../src/error/ErrUnderlying.sol";
import {UNDERLYING_SNAPSHOT_ROOT} from "../../../../src/generated/LibUnderlyingSnapshotCode.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";

/// @dev A Base block before any production vault has its underlying ticker
/// and name set, with the NVDA pair reporting its initialized metadata.
uint256 constant NAMING_PRE_ROLLOUT_BLOCK_BASE = 52662900;

/// @title UnderlyingNamingUpgradeShadowForkTest
/// @notice Applies the current corporate-actions facet, receipt vault and
/// wrapped token vault implementations to the live Base NVDA pair on a fork
/// pinned before the rollout. `testRecommendedRolloutOrder` runs the order
/// the rollout uses (facet deployed, wrapper upgrade, vault upgrade,
/// `setUnderlying`) and checks metadata and supply after every step. The
/// other tests cover single steps, the vault-first order, and a vault
/// upgraded before its facet or the snapshot exists.
///
/// @dev Implementations are planted at their deterministic candidate addresses
/// with `deployCodeTo`, so constructors (the facet's `_SELF`) run in place, the
/// snapshot is Zoltu-deployed at its constant address, and each beacon is
/// upgraded by its live owner.
contract UnderlyingNamingUpgradeShadowForkTest is Test {
    IERC20Metadata internal constant VAULT = IERC20Metadata(LibTokenInvariants.NVDA_RECEIPT_VAULT);
    IERC4626 internal constant WRAPPER = IERC4626(LibTokenInvariants.NVDA_WRAPPED_TOKEN_VAULT);

    string internal sVaultNameBefore;
    string internal sVaultSymbolBefore;
    string internal sWrapperNameBefore;
    string internal sWrapperSymbolBefore;
    string internal sReceiptNameBefore;
    string internal sReceiptSymbolBefore;
    uint256 internal sVaultSupplyBefore;
    uint256 internal sWrapperSupplyBefore;
    uint256 internal sWrapperAssetsBefore;

    function setUp() public {
        vm.createSelectFork(LibRainDeploy.BASE, NAMING_PRE_ROLLOUT_BLOCK_BASE);

        sVaultNameBefore = VAULT.name();
        sVaultSymbolBefore = VAULT.symbol();
        sWrapperNameBefore = WRAPPER.name();
        sWrapperSymbolBefore = WRAPPER.symbol();
        IReceiptV3 receipt = receiptOf();
        sReceiptNameBefore = receipt.name();
        sReceiptSymbolBefore = receipt.symbol();
        sVaultSupplyBefore = VAULT.totalSupply();
        sWrapperSupplyBefore = WRAPPER.totalSupply();
        sWrapperAssetsBefore = WRAPPER.totalAssets();

        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            LibProdDeployCurrent.STOX_CORPORATE_ACTIONS_FACET
        );
        deployCodeTo("src/concrete/StoxReceiptVault.sol:StoxReceiptVault", LibProdDeployCurrent.STOX_RECEIPT_VAULT);
        deployCodeTo(
            "src/concrete/StoxWrappedTokenVault.sol:StoxWrappedTokenVault",
            LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT
        );
        LibTestDeploy.deployUnderlyingSnapshot(vm);
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
        IStoxUnderlyingV2(address(VAULT)).setUnderlying("NVDA", "NVIDIA Corporation", "US67066G1040");
    }

    function assertSupplyIntact() internal view {
        assertEq(VAULT.totalSupply(), sVaultSupplyBefore, "vault supply moved");
        assertEq(WRAPPER.totalSupply(), sWrapperSupplyBefore, "wrapper supply moved");
        assertEq(WRAPPER.totalAssets(), sWrapperAssetsBefore, "wrapper assets moved");
    }

    function assertMetadataUnchanged() internal view {
        assertEq(VAULT.symbol(), sVaultSymbolBefore, "vault symbol moved");
        assertEq(VAULT.name(), sVaultNameBefore, "vault name moved");
        assertEq(WRAPPER.symbol(), sWrapperSymbolBefore, "wrapper symbol moved");
        assertEq(WRAPPER.name(), sWrapperNameBefore, "wrapper name moved");
        assertEq(receiptOf().symbol(), sReceiptSymbolBefore, "receipt symbol moved");
        assertEq(receiptOf().name(), sReceiptNameBefore, "receipt name moved");
    }

    /// At the pinned block the pair reports its initialized metadata, which
    /// the wrapper derives as "Wrapped " / "w".
    function testPreRolloutBaseline() external view {
        assertEq(sVaultSymbolBefore, "tNVDA");
        assertEq(sVaultNameBefore, "NVIDIA Corporation ST0x");
        assertEq(sWrapperSymbolBefore, "wtNVDA");
        assertEq(sWrapperNameBefore, "Wrapped NVIDIA Corporation ST0x");
    }

    /// The rollout order: wrapper upgrade, vault upgrade, then
    /// `setUnderlying`. No visible metadata moves until the final step, which
    /// renames both tokens together.
    function testRecommendedRolloutOrder() external {
        upgradeWrapper();
        assertMetadataUnchanged();
        assertSupplyIntact();

        upgradeVault();
        assertEq(IStoxUnderlyingV2(address(VAULT)).underlyingSymbol(), "");
        assertMetadataUnchanged();
        assertSupplyIntact();

        setNvda();
        assertEq(VAULT.symbol(), "tNVDA");
        assertEq(VAULT.name(), "NVIDIA Corporation (ST0x)");
        assertEq(WRAPPER.symbol(), "NVDAs");
        assertEq(WRAPPER.name(), "NVIDIA Corporation (ST0x)");
        assertEq(receiptOf().symbol(), sReceiptSymbolBefore);
        assertSupplyIntact();
    }

    /// Not the recommended order: with the vault upgraded and the underlying
    /// set before the wrapper upgrade, the live wrapper shows an interim
    /// "Wrapped <name> (ST0x)" until its own upgrade lands.
    function testVaultFirstOrderShowsInterimWrapperName() external {
        upgradeVault();
        setNvda();
        assertEq(WRAPPER.symbol(), "wtNVDA");
        assertEq(WRAPPER.name(), "Wrapped NVIDIA Corporation (ST0x)");

        upgradeWrapper();
        assertEq(WRAPPER.symbol(), "NVDAs");
        assertEq(WRAPPER.name(), "NVIDIA Corporation (ST0x)");
        assertSupplyIntact();
    }

    /// A vault upgraded before the facet exists keeps its supply, and its
    /// metadata and every facet call, `setUnderlying` included, revert rather
    /// than succeeding as a no-op. This is why the facet deploy comes first.
    function testVaultUpgradeBeforeFacetDeploy() external {
        address facet = LibProdDeployCurrent.STOX_CORPORATE_ACTIONS_FACET;
        vm.etch(facet, "");
        upgradeVault();
        assertSupplyIntact();
        vm.expectRevert(abi.encodeWithSelector(CorporateActionsFacetNotDeployed.selector, facet));
        VAULT.name();
        vm.expectRevert(abi.encodeWithSelector(CorporateActionsFacetNotDeployed.selector, facet));
        VAULT.symbol();
        vm.expectRevert(abi.encodeWithSelector(CorporateActionsFacetNotDeployed.selector, facet));
        ICorporateActionsV1(address(VAULT)).completedActionCount();
        address owner = OwnableUpgradeable(address(VAULT)).owner();
        vm.expectRevert(abi.encodeWithSelector(CorporateActionsFacetNotDeployed.selector, facet));
        vm.prank(owner);
        IStoxUnderlyingV2(address(VAULT)).setUnderlying("NVDA", "NVIDIA Corporation", "US67066G1040");
    }

    /// A vault upgraded before the snapshot exists keeps its supply, and its
    /// name and symbol revert rather than falling back to its stored values.
    function testVaultUpgradeBeforeSnapshotDeploy() external {
        vm.etch(UNDERLYING_SNAPSHOT_ROOT, "");
        upgradeVault();
        assertSupplyIntact();
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingSnapshot.selector, UNDERLYING_SNAPSHOT_ROOT));
        VAULT.name();
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingSnapshot.selector, UNDERLYING_SNAPSHOT_ROOT));
        VAULT.symbol();
    }

    /// Only the vault owner sets the underlying on a live vault.
    function testLiveNonOwnerCannotSet(address caller) external {
        upgradeVault();
        vm.assume(caller != OwnableUpgradeable(address(VAULT)).owner());
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        IStoxUnderlyingV2(address(VAULT)).setUnderlying("NVDA", "NVIDIA Corporation", "US67066G1040");
    }
}
