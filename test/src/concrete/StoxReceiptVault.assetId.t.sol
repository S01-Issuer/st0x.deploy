// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {IAuthorizeV1} from "rain-vats-0.2.25/src/interface/IAuthorizeV1.sol";
import {CloneFactory} from "rain-factory-deploy-0.2.14/src/concrete/CloneFactory.sol";
import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {IStoxAssetIdV1} from "../../../src/interface/IStoxAssetIdV1.sol";
import {IStoxUnderlyingV2} from "../../../src/interface/IStoxUnderlyingV2.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {MovedFacetStoxReceiptVault} from "../../concrete/MovedFacetStoxReceiptVault.sol";

contract StoxReceiptVaultAssetIdTest is Test {
    address internal constant AUTHORITY = address(uint160(uint256(keccak256("AUTHORITY"))));
    address internal constant OWNER = address(uint160(uint256(keccak256("OWNER"))));
    bytes32 internal constant RBAC_NAME = keccak256("st0x.rbac.test.v1");
    string internal constant NVDA_ISIN = "US67066G1040";
    string internal constant AAPL_ISIN = "US0378331005";
    string internal constant META_ISIN = "US30303M1027";

    function setUp() external {
        LibTestDeploy.deployAll(vm);
        address facet = LibRainDeploy.deployZoltu(type(StoxCorporateActionsFacet).creationCode);
        require(facet == LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, "facet address mismatch");
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        IAuthorizeV1 authorizer = IAuthorizeV1(
            new CloneFactory()
                .cloneDeterministic(
                    address(impl), LibTestDeploy.authorizerData(vm, OWNER), bytes32(uint256(uint160(address(impl))))
                )
        );
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, authorizer);
    }

    function newVault(string memory assetId, string memory listingTicker, string memory listingName)
        internal
        returns (IStoxAssetIdV1)
    {
        return IStoxAssetIdV1(
            address(
                LibTestDeploy.newVault(
                    AUTHORITY, LibTestDeploy.vaultData(assetId, listingTicker, listingName, AUTHORITY, RBAC_NAME)
                )
            )
        );
    }

    function upgradeVaultBeacon(address implementation) internal {
        vm.prank(LibProdDeployV1.BEACON_INITIAL_OWNER);
        UpgradeableBeacon(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1).upgradeTo(implementation);
    }

    /// Unset, `assetId()` falls back to the asset id each vault was initialized with.
    function testUnsetAssetIdIsTheInitializedAssetId() external {
        IStoxAssetIdV1 nvda = newVault(NVDA_ISIN, "NVDA", "NVIDIA Corporation");
        IStoxAssetIdV1 aapl = newVault(AAPL_ISIN, "AAPL", "Apple Inc.");
        assertEq(nvda.assetId(), NVDA_ISIN);
        assertEq(aapl.assetId(), AAPL_ISIN);
    }

    /// `assetId()` reports each `setUnderlying` ISIN, and only on the vault it was set on.
    function testAssetIdFollowsSetUnderlyingIsin() external {
        IStoxAssetIdV1 vault = newVault(NVDA_ISIN, "NVDA", "NVIDIA Corporation");
        IStoxAssetIdV1 other = newVault(AAPL_ISIN, "AAPL", "Apple Inc.");
        vm.prank(OWNER);
        IStoxUnderlyingV2(address(vault)).setUnderlying("NVDQ", "NVIDIA Corp", META_ISIN);
        assertEq(vault.assetId(), META_ISIN, "first set");
        vm.prank(OWNER);
        IStoxUnderlyingV2(address(vault)).setUnderlying("NVDQ", "NVIDIA Corp", NVDA_ISIN);
        assertEq(vault.assetId(), NVDA_ISIN, "second set");
        assertEq(other.assetId(), AAPL_ISIN, "other vault");
    }

    /// `UnderlyingSet`'s old ISIN is `assetId()` before the update: the initialized asset id on the first set, the
    /// previous override after.
    function testUnderlyingSetOldIsinIsThePriorAssetId() external {
        IStoxAssetIdV1 vault = newVault(NVDA_ISIN, "NVDA", "NVIDIA Corporation");
        string[2] memory newIsins = [META_ISIN, AAPL_ISIN];
        string[2] memory priors = [NVDA_ISIN, META_ISIN];
        for (uint256 i = 0; i < newIsins.length; i++) {
            string memory prior = vault.assetId();
            assertEq(prior, priors[i]);
            vm.recordLogs();
            vm.prank(OWNER);
            IStoxUnderlyingV2(address(vault)).setUnderlying("NVDA", "NVIDIA Corporation", newIsins[i]);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(logs.length, 1);
            assertEq(logs[0].topics[0], IStoxUnderlyingV2.UnderlyingSet.selector);
            (,, string memory oldIsin,,, string memory newIsin) =
                abi.decode(logs[0].data, (string, string, string, string, string, string));
            assertEq(oldIsin, prior);
            assertEq(newIsin, newIsins[i]);
        }
    }

    /// The set ISIN survives a beacon upgrade to an implementation whose fallback delegatecalls a facet at another
    /// address with the pinned facet gone, and the upgrade back.
    function testAssetIdSurvivesSetUnderlyingAndAFacetMove() external {
        IStoxAssetIdV1 vault = newVault(NVDA_ISIN, "NVDA", "NVIDIA Corporation");
        vm.prank(OWNER);
        IStoxUnderlyingV2(address(vault)).setUnderlying("NVDQ", "NVIDIA Corp", META_ISIN);
        assertEq(vault.assetId(), META_ISIN, "after setUnderlying");

        address facet = LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE;
        bytes memory facetCode = facet.code;
        address moved = address(new MovedFacetStoxReceiptVault(address(new StoxCorporateActionsFacet())));
        upgradeVaultBeacon(moved);
        assertEq(UpgradeableBeacon(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1).implementation(), moved, "upgraded");
        vm.etch(facet, "");
        assertEq(vault.assetId(), META_ISIN, "moved");

        vm.etch(facet, facetCode);
        upgradeVaultBeacon(LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE);
        assertEq(
            UpgradeableBeacon(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1).implementation(),
            LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE,
            "upgraded back"
        );
        assertEq(vault.assetId(), META_ISIN, "back");
    }
}
