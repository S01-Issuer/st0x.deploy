// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {IStoxUnderlyingV2} from "../../../src/interface/IStoxUnderlyingV2.sol";
import {
    MalformedUnderlyingSymbol,
    MalformedUnderlyingName,
    MalformedUnderlyingIsin
} from "../../../src/error/ErrUnderlying.sol";
import {CorporateActionsFacetNotDeployed} from "../../../src/error/ErrCorporateAction.sol";
import {LibSecurity, UNDERLYING_STORAGE_LOCATION, ST0X_NAME_SUFFIX} from "../../../src/lib/LibSecurity.sol";
import {ERC20_STORAGE_LOCATION} from "../../../src/lib/LibERC20Storage.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {OwnedStoxReceiptVault} from "./OwnedStoxReceiptVault.sol";
import {UnderlyingSetForwarder} from "../../concrete/UnderlyingSetForwarder.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

/// `IStoxUnderlyingV2.setUnderlying` on a bare vault that no snapshot row
/// names, so every set value is an override that applies.
contract StoxReceiptVaultUnderlyingTest is Test {
    address internal constant OWNER = address(0x0123);
    string internal constant NVDA_ISIN = "US67066G1040";
    string internal constant META_ISIN = "US30303M1027";

    StoxReceiptVault internal sVault;

    function setUp() public {
        // `_SELF` must match the address the vault's `fallback()` delegatecalls.
        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE
        );
        LibTestDeploy.deployUnderlyingSnapshot(vm);
        sVault = new OwnedStoxReceiptVault(OWNER);
    }

    function underlying() internal view returns (IStoxUnderlyingV2) {
        return IStoxUnderlyingV2(address(sVault));
    }

    function testStorageLocation() external pure {
        assertEq(
            UNDERLYING_STORAGE_LOCATION,
            keccak256(abi.encode(uint256(keccak256("rain.storage.underlying.1")) - 1)) & ~bytes32(uint256(0xff))
        );
        assertEq(UNDERLYING_STORAGE_LOCATION, 0xc5c1ed5563e8e77e516055b037edac16f1d2acbaba4a5d944a7dc6677225a100);
    }

    /// The struct is append-only behind a beacon, so the field offsets are positional.
    function testStorageLayoutPin() external {
        vm.warp(1_800_000_000);
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA", NVDA_ISIN);
        assertEq(
            vm.load(address(sVault), UNDERLYING_STORAGE_LOCATION),
            bytes32(0x4e56444100000000000000000000000000000000000000000000000000000008)
        );
        assertEq(
            vm.load(address(sVault), bytes32(uint256(UNDERLYING_STORAGE_LOCATION) + 1)),
            bytes32(0x4e5649444941000000000000000000000000000000000000000000000000000c)
        );
        assertEq(
            vm.load(address(sVault), bytes32(uint256(UNDERLYING_STORAGE_LOCATION) + 2)),
            bytes32(0x5553363730363647313034300000000000000000000000000000000000000018)
        );
        assertEq(
            vm.load(address(sVault), bytes32(uint256(UNDERLYING_STORAGE_LOCATION) + 3)), bytes32(uint256(1_800_000_000))
        );
    }

    function testSetUnderlyingStampsBlockTimestamp(uint32 timestamp) external {
        vm.assume(timestamp > 0);
        vm.warp(timestamp);
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation", NVDA_ISIN);
        assertEq(
            vm.load(address(sVault), bytes32(uint256(UNDERLYING_STORAGE_LOCATION) + 3)), bytes32(uint256(timestamp))
        );
    }

    function testSetUnderlyingLeavesOzErc20SlotsUntouched() external {
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA", NVDA_ISIN);
        assertEq(vm.load(address(sVault), bytes32(uint256(ERC20_STORAGE_LOCATION) + 3)), bytes32(0));
        assertEq(vm.load(address(sVault), bytes32(uint256(ERC20_STORAGE_LOCATION) + 4)), bytes32(0));
    }

    /// Only the timestamp marks an override as set.
    function testUnderlyingValuesWithoutTimestampAreNotAnOverride() external {
        vm.store(
            address(sVault),
            UNDERLYING_STORAGE_LOCATION,
            bytes32(0x4e56444100000000000000000000000000000000000000000000000000000008)
        );
        vm.store(
            address(sVault),
            bytes32(uint256(UNDERLYING_STORAGE_LOCATION) + 1),
            bytes32(0x4e5649444941000000000000000000000000000000000000000000000000000c)
        );
        assertEq(underlying().underlyingSymbol(), "");
        assertEq(underlying().underlyingName(), "");
        assertEq(sVault.symbol(), "");
        assertEq(sVault.name(), "");
    }

    function testGettersUnset() external view {
        assertEq(underlying().underlyingSymbol(), "");
        assertEq(underlying().underlyingName(), "");
        assertEq(underlying().underlyingIsin(), "");
    }

    function testSymbolAndNameUnsetFallBackToStoredValues() external {
        vm.store(
            address(sVault),
            bytes32(uint256(ERC20_STORAGE_LOCATION) + 3),
            bytes32(0x4e5649444941000000000000000000000000000000000000000000000000000c)
        );
        vm.store(
            address(sVault),
            bytes32(uint256(ERC20_STORAGE_LOCATION) + 4),
            bytes32(0x4e56444100000000000000000000000000000000000000000000000000000008)
        );
        assertEq(sVault.name(), "NVIDIA");
        assertEq(sVault.symbol(), "NVDA");
    }

    function testSetUnderlyingStoresValues() external {
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation", NVDA_ISIN);
        assertEq(underlying().underlyingSymbol(), "NVDA");
        assertEq(underlying().underlyingName(), "NVIDIA Corporation");
        assertEq(underlying().underlyingIsin(), NVDA_ISIN);
    }

    function testSymbolAndNameDerivedFromUnderlying() external {
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation", NVDA_ISIN);
        assertEq(sVault.symbol(), "tNVDA");
        assertEq(sVault.name(), "NVIDIA Corporation (ST0x)");
    }

    function testSymbolAndNameDerivedFromUnderlyingFuzz(bytes32 symbolSeed, uint256 symbolLength, bytes memory nameSeed)
        external
    {
        bytes memory tickerAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.";
        bytes memory newSymbol = new bytes(bound(symbolLength, 1, 16));
        for (uint256 byteIndex = 0; byteIndex < newSymbol.length; byteIndex++) {
            newSymbol[byteIndex] = tickerAlphabet[uint8(symbolSeed[byteIndex]) % tickerAlphabet.length];
        }
        bytes memory newName = new bytes(nameSeed.length);
        for (uint256 byteIndex = 0; byteIndex < newName.length; byteIndex++) {
            bytes1 printable = bytes1(0x20 + uint8(nameSeed[byteIndex]) % 0x5f);
            newName[byteIndex] = printable == "\"" || printable == "\\" ? bytes1(0x20) : printable;
        }
        vm.assume(LibSecurity.nameWellFormed(newName));
        vm.prank(OWNER);
        underlying().setUnderlying(string(newSymbol), string(newName), NVDA_ISIN);
        assertEq(sVault.symbol(), string.concat("t", string(newSymbol)));
        assertEq(sVault.name(), string.concat(string(newName), ST0X_NAME_SUFFIX));
    }

    function testSetUnderlyingEmitsEvent() external {
        vm.expectEmit(address(sVault));
        emit IStoxUnderlyingV2.UnderlyingSet(OWNER, "", "", "", "NVDA", "NVIDIA Corporation", NVDA_ISIN);
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation", NVDA_ISIN);
    }

    /// Checked against the raw log, not the interface's own declaration.
    function testUnderlyingSetIndexesSender() external {
        vm.recordLogs();
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation", NVDA_ISIN);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(sVault));
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256("UnderlyingSet(address,string,string,string,string,string,string)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(OWNER))));
        assertEq(logs[0].data, abi.encode("", "", "", "NVDA", "NVIDIA Corporation", NVDA_ISIN));
    }

    function testSetUnderlyingOverwrites() external {
        vm.warp(100);
        vm.prank(OWNER);
        underlying().setUnderlying("FB", "Meta Platforms, Inc.", META_ISIN);

        vm.warp(200);
        vm.expectEmit(address(sVault));
        emit IStoxUnderlyingV2.UnderlyingSet(
            OWNER, "FB", "Meta Platforms, Inc.", META_ISIN, "META", "Meta Platforms Inc", NVDA_ISIN
        );
        vm.prank(OWNER);
        underlying().setUnderlying("META", "Meta Platforms Inc", NVDA_ISIN);

        assertEq(underlying().underlyingSymbol(), "META");
        assertEq(underlying().underlyingName(), "Meta Platforms Inc");
        assertEq(underlying().underlyingIsin(), NVDA_ISIN);
        assertEq(sVault.symbol(), "tMETA");
        assertEq(sVault.name(), "Meta Platforms Inc (ST0x)");
        assertEq(vm.load(address(sVault), bytes32(uint256(UNDERLYING_STORAGE_LOCATION) + 3)), bytes32(uint256(200)));
    }

    function testSetUnderlyingNonOwnerReverts(address caller) external {
        vm.assume(caller != OWNER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation", NVDA_ISIN);
    }

    function testSetUnderlyingRejectsContractCallerWithOwnerOrigin() external {
        UnderlyingSetForwarder forwarder = new UnderlyingSetForwarder();
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(forwarder))
        );
        vm.prank(OWNER, OWNER);
        forwarder.forward(underlying(), "NVDA", "NVIDIA Corporation", NVDA_ISIN);
        assertEq(underlying().underlyingSymbol(), "");
        assertEq(underlying().underlyingName(), "");
        assertEq(underlying().underlyingIsin(), "");
    }

    function testSetUnderlyingRejectsNonOwnerSenderWithOwnerOrigin(address caller) external {
        vm.assume(caller != OWNER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller, OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation", NVDA_ISIN);
        assertEq(underlying().underlyingSymbol(), "");
        assertEq(underlying().underlyingName(), "");
        assertEq(underlying().underlyingIsin(), "");
    }

    /// A ticker init would refuse as a listing is rejected, the empty one included.
    function testSetUnderlyingMalformedSymbolReverts() external {
        string[4] memory symbols = ["", "nvda", "NV DA", "AAAAAAAAAAAAAAAAA"];
        for (uint256 i = 0; i < symbols.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingSymbol.selector, symbols[i]));
            vm.prank(OWNER);
            underlying().setUnderlying(symbols[i], "NVIDIA Corporation", NVDA_ISIN);
        }
        assertEq(underlying().underlyingSymbol(), "");
    }

    /// "t" + a 16-byte ticker is the longest symbol; mints cap it at 31 bytes.
    function testSetUnderlyingTickerLengthBoundary() external {
        vm.prank(OWNER);
        underlying().setUnderlying("ABCDEFGHIJKLMNOP", "NVIDIA Corporation", NVDA_ISIN);
        assertEq(sVault.symbol(), "tABCDEFGHIJKLMNOP");
        assertLe(bytes(sVault.symbol()).length, 31);

        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingSymbol.selector, "ABCDEFGHIJKLMNOPQ"));
        vm.prank(OWNER);
        underlying().setUnderlying("ABCDEFGHIJKLMNOPQ", "NVIDIA Corporation", NVDA_ISIN);
    }

    /// A name init would refuse as a listing is rejected, the empty one included.
    function testSetUnderlyingMalformedNameReverts() external {
        string[6] memory names = [
            "",
            "NVIDIA \"Corporation\"",
            "NVIDIA\\Corporation",
            "NVIDIA\nCorporation",
            "NVIDIA (ST0x)",
            "NVIDIA Corporation (ST0x)"
        ];
        for (uint256 i = 0; i < names.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingName.selector, names[i]));
            vm.prank(OWNER);
            underlying().setUnderlying("NVDA", names[i], NVDA_ISIN);
        }
        assertEq(underlying().underlyingName(), "");
    }

    /// An ISIN init would refuse as an asset id is rejected, the empty one included.
    function testSetUnderlyingMalformedIsinReverts() external {
        string[3] memory isins = ["", "US67066G1041", "us67066g1040"];
        for (uint256 i = 0; i < isins.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingIsin.selector, isins[i]));
            vm.prank(OWNER);
            underlying().setUnderlying("NVDA", "NVIDIA Corporation", isins[i]);
        }
        assertEq(underlying().underlyingIsin(), "");
    }

    /// The checks run ticker, then name, then ISIN.
    function testSetUnderlyingChecksInOrder() external {
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingSymbol.selector, ""));
        vm.prank(OWNER);
        underlying().setUnderlying("", "", "");
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingName.selector, ""));
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "", "");
    }

    /// A non-owner learns nothing from the revert about which input was bad.
    function testSetUnderlyingNonOwnerMalformedRevertsUnauthorized() external {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        underlying().setUnderlying("", "", "");
    }

    function testRejectedSetLeavesValuesUntouched() external {
        vm.warp(100);
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation", NVDA_ISIN);
        vm.warp(200);
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingIsin.selector, "US67066G1041"));
        vm.prank(OWNER);
        underlying().setUnderlying("AAPL", "Apple Inc.", "US67066G1041");
        assertEq(sVault.symbol(), "tNVDA");
        assertEq(sVault.name(), "NVIDIA Corporation (ST0x)");
        assertEq(underlying().underlyingIsin(), NVDA_ISIN);
        assertEq(vm.load(address(sVault), bytes32(uint256(UNDERLYING_STORAGE_LOCATION) + 3)), bytes32(uint256(100)));
    }

    function testFacetCallsRevertWithoutFacet() external {
        address facet = LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE;
        vm.etch(facet, "");
        vm.expectRevert(abi.encodeWithSelector(CorporateActionsFacetNotDeployed.selector, facet));
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation", NVDA_ISIN);
        vm.expectRevert(abi.encodeWithSelector(CorporateActionsFacetNotDeployed.selector, facet));
        underlying().underlyingSymbol();
        vm.expectRevert(abi.encodeWithSelector(CorporateActionsFacetNotDeployed.selector, facet));
        underlying().underlyingName();
        vm.expectRevert(abi.encodeWithSelector(CorporateActionsFacetNotDeployed.selector, facet));
        underlying().underlyingIsin();
        vm.expectRevert(abi.encodeWithSelector(CorporateActionsFacetNotDeployed.selector, facet));
        sVault.symbol();
        vm.expectRevert(abi.encodeWithSelector(CorporateActionsFacetNotDeployed.selector, facet));
        sVault.name();
    }

    function testFacetDirectCallsRevert() external {
        StoxCorporateActionsFacet facet =
            StoxCorporateActionsFacet(LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE);
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        facet.underlyingSymbol();
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        facet.underlyingName();
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        facet.underlyingIsin();
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        facet.name();
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        facet.symbol();
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        facet.setUnderlying("NVDA", "NVIDIA Corporation", NVDA_ISIN);
    }
}
