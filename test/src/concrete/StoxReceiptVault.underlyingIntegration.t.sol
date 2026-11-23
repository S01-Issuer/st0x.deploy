// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAuthorizeV1} from "rain-vats-0.2.25/src/interface/IAuthorizeV1.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.25/src/interface/IReceiptVaultV3.sol";
import {IReceiptV3} from "rain-vats-0.2.25/src/interface/IReceiptV3.sol";
import {CloneFactory} from "rain-factory-deploy-0.2.14/src/concrete/CloneFactory.sol";
import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {IStoxUnderlyingV2} from "../../../src/interface/IStoxUnderlyingV2.sol";
import {CorporateActionsFacetNotDeployed} from "../../../src/error/ErrCorporateAction.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {ST0X_NAME_SUFFIX} from "../../../src/lib/LibSecurity.sol";
import {LibTokenMetadata} from "../../../src/lib/LibTokenMetadata.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

/// End-to-end naming for a token pair built as in production (registry beacon
/// proxies over the candidate implementations): the tStock and its wrapper
/// carry the names built from the listing ticker and name until the owner
/// sets the underlying ticker and name, then the names built from those.
contract StoxUnderlyingIntegrationTest is Test {
    address internal constant AUTHORITY = address(uint160(uint256(keccak256("AUTHORITY"))));
    bytes32 internal constant RBAC_NAME = keccak256("st0x.rbac.test.v1");
    string internal constant NVDA_ISIN = "US67066G1040";
    string internal constant META_ISIN = "US30303M1027";
    string internal constant NEW_ISIN = "US0378331005";

    StoxReceiptVault internal sVault;
    StoxWrappedTokenVault internal sWrapper;

    function setUp() public {
        LibTestDeploy.deployAll(vm);
        address facet = LibRainDeploy.deployZoltu(type(StoxCorporateActionsFacet).creationCode);
        require(facet == LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, "facet address mismatch");

        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        IAuthorizeV1 authorizer = IAuthorizeV1(
            new CloneFactory()
                .cloneDeterministic(
                    address(impl),
                    LibTestDeploy.authorizerData(vm, address(this)),
                    bytes32(uint256(uint160(address(impl))))
                )
        );
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, address(this), authorizer);
        sVault = LibTestDeploy.newVault(
            AUTHORITY, LibTestDeploy.vaultData(NVDA_ISIN, "NVDA", "NVIDIA Corporation", AUTHORITY, RBAC_NAME)
        );
        sWrapper = LibTestDeploy.newWrapper(AUTHORITY, address(sVault));
    }

    function repeated(bytes1 fill, uint256 length) internal pure returns (string memory) {
        bytes memory out = new bytes(length);
        for (uint256 byteIndex = 0; byteIndex < length; byteIndex++) {
            out[byteIndex] = fill;
        }
        return string(out);
    }

    /// The wrapper's probe of its asset is not starved of gas by a long
    /// name read cold through the real proxy, fallback and facet path.
    function testLongUnderlyingDerivesThroughWrapper() external {
        string memory ticker = repeated("A", 16);
        string memory longName = repeated("N", 4096);
        IStoxUnderlyingV2(address(sVault)).setUnderlying(ticker, longName, NVDA_ISIN);
        vm.cool(address(sVault));
        assertEq(sWrapper.symbol(), string.concat(ticker, "s"));
        vm.cool(address(sVault));
        assertEq(sWrapper.name(), string.concat(longName, ST0X_NAME_SUFFIX));
    }

    /// Unset: the underlying getters fall back to the listing ticker and
    /// name, so both tokens carry the names built from them.
    function testUnsetFallsBackToTheListingTickerAndName() external view {
        assertEq(IStoxUnderlyingV2(address(sVault)).underlyingSymbol(), "NVDA");
        assertEq(IStoxUnderlyingV2(address(sVault)).underlyingName(), "NVIDIA Corporation");
        assertEq(sVault.symbol(), "tNVDA");
        assertEq(sVault.name(), "NVIDIA Corporation (ST0x)");
        assertEq(sWrapper.symbol(), "NVDAs");
        assertEq(sWrapper.name(), "NVIDIA Corporation (ST0x)");
    }

    /// Set: both tokens carry the names built from the underlying ticker and
    /// name.
    function testDerivedFromUnderlying() external {
        IStoxUnderlyingV2(address(sVault)).setUnderlying("NVDX", "NVIDIA Holdings", NEW_ISIN);
        assertEq(sVault.symbol(), "tNVDX");
        assertEq(sVault.name(), "NVIDIA Holdings (ST0x)");
        assertEq(sWrapper.symbol(), "NVDXs");
        assertEq(sWrapper.name(), "NVIDIA Holdings (ST0x)");
    }

    /// With no facet code at the pinned address, `setUnderlying` reverts
    /// rather than succeeding as a no-op, and the metadata is untouched.
    function testSetUnderlyingRevertsWithoutFacet() external {
        address facet = LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE;
        vm.etch(facet, "");
        vm.expectRevert(abi.encodeWithSelector(CorporateActionsFacetNotDeployed.selector, facet));
        IStoxUnderlyingV2(address(sVault)).setUnderlying("NVDX", "NVIDIA Holdings", NEW_ISIN);
        assertEq(sVault.symbol(), "tNVDA");
        assertEq(sVault.name(), "NVIDIA Corporation (ST0x)");
    }

    /// Once set, the tStock's metadata is plain ERC-20 storage: reading it
    /// needs no facet.
    function testSetMetadataReadsWithoutFacet() external {
        IStoxUnderlyingV2(address(sVault)).setUnderlying("NVDX", "NVIDIA Holdings", NEW_ISIN);
        vm.etch(LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, "");
        assertEq(sVault.symbol(), "tNVDX");
        assertEq(sVault.name(), "NVIDIA Holdings (ST0x)");
    }

    /// The ERC-1155 receipt builds its name and symbol from the vault's
    /// `symbol()`, which reads "t" + ticker either way.
    function testReceiptFollowsVaultSymbol() external {
        IReceiptV3 receipt = IReceiptV3(address(IReceiptVaultV3(payable(address(sVault))).receipt()));
        string memory receiptSymbolBefore = receipt.symbol();
        string memory receiptNameBefore = receipt.name();
        IStoxUnderlyingV2(address(sVault)).setUnderlying("NVDA", "NVIDIA Corporation", NVDA_ISIN);
        assertEq(receipt.symbol(), receiptSymbolBefore);
        assertEq(receipt.name(), receiptNameBefore);
    }

    /// A ticker change moves both tokens' metadata with it.
    function testRenameFollowsThrough() external {
        IStoxUnderlyingV2(address(sVault)).setUnderlying("FB", "Meta Platforms, Inc.", META_ISIN);
        assertEq(sWrapper.symbol(), "FBs");
        IStoxUnderlyingV2(address(sVault)).setUnderlying("META", "Meta Platforms, Inc.", META_ISIN);
        assertEq(sVault.symbol(), "tMETA");
        assertEq(sWrapper.symbol(), "METAs");
        assertEq(sWrapper.name(), "Meta Platforms, Inc. (ST0x)");
    }

    function testVaultAndWrapperHaveTheTokenMetadataDecimals() external view {
        assertEq(sVault.decimals(), LibTokenMetadata.RECEIPT_VAULT_DECIMALS);
        assertEq(sWrapper.decimals(), LibTokenMetadata.WRAPPED_TOKEN_VAULT_DECIMALS);
    }
}
