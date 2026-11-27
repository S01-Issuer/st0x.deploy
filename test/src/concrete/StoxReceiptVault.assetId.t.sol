// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {IAuthorizeV1} from "rain-vats-0.2.25/src/interface/IAuthorizeV1.sol";
import {CloneFactory} from "rain-factory-deploy-0.2.14/src/concrete/CloneFactory.sol";
import {LibRainDeploy} from "rain-deploy-0.1.43/src/lib/LibRainDeploy.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {IStoxAssetIdV1} from "../../../src/interface/IStoxAssetIdV1.sol";
import {IStoxUnderlyingV1} from "../../../src/interface/IStoxUnderlyingV1.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {MovedFacetStoxReceiptVault} from "../../concrete/MovedFacetStoxReceiptVault.sol";

contract StoxReceiptVaultAssetIdTest is Test {
    address internal constant AUTHORITY = address(uint160(uint256(keccak256("AUTHORITY"))));
    address internal constant OWNER = address(uint160(uint256(keccak256("OWNER"))));
    bytes32 internal constant RBAC_NAME = keccak256("st0x.rbac.test.v1");

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

    function testAssetIdIsTheInitializedAssetId() external {
        IStoxAssetIdV1 nvda = newVault("US67066G1040", "NVDA", "NVIDIA Corporation");
        IStoxAssetIdV1 aapl = newVault("US0378331005", "AAPL", "Apple Inc.");
        assertEq(nvda.assetId(), "US67066G1040");
        assertEq(aapl.assetId(), "US0378331005");
    }

    /// The asset id survives `setUnderlying`, a beacon upgrade to an implementation whose fallback delegatecalls a
    /// facet at another address with the pinned facet gone, and the upgrade back.
    function testAssetIdSurvivesSetUnderlyingAndAFacetMove() external {
        IStoxAssetIdV1 vault = newVault("US67066G1040", "NVDA", "NVIDIA Corporation");
        vm.prank(OWNER);
        IStoxUnderlyingV1(address(vault)).setUnderlying("NVDQ", "NVIDIA Corp");
        assertEq(IStoxUnderlyingV1(address(vault)).underlyingSymbol(), "NVDQ", "underlying set");
        assertEq(vault.assetId(), "US67066G1040", "after setUnderlying");

        address facet = LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE;
        bytes memory facetCode = facet.code;
        address moved = address(new MovedFacetStoxReceiptVault(address(new StoxCorporateActionsFacet())));
        upgradeVaultBeacon(moved);
        assertEq(UpgradeableBeacon(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1).implementation(), moved, "upgraded");
        vm.etch(facet, "");
        assertEq(vault.assetId(), "US67066G1040", "moved");

        vm.etch(facet, facetCode);
        upgradeVaultBeacon(LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE);
        assertEq(
            UpgradeableBeacon(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1).implementation(),
            LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE,
            "upgraded back"
        );
        assertEq(vault.assetId(), "US67066G1040", "back");
    }
}
