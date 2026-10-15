// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {IStoxUnderlyingV1} from "../../../src/interface/IStoxUnderlyingV1.sol";
import {EmptyUnderlyingSymbol, EmptyUnderlyingName} from "../../../src/error/ErrUnderlying.sol";
import {UNDERLYING_STORAGE_LOCATION, ST0X_NAME_SUFFIX} from "../../../src/lib/LibUnderlying.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {OwnedStoxReceiptVault} from "./OwnedStoxReceiptVault.sol";

/// Unit tests for the underlying ticker/name surface (`IStoxUnderlyingV1`,
/// implemented by `StoxCorporateActionsFacet`) and the `symbol()` / `name()`
/// the vault builds from it. The vault is constructed bare (not initialized),
/// so its stored ERC-20 name and symbol are empty: the unset fallback to
/// initialized values is covered end-to-end in
/// `StoxUnderlyingIntegrationTest`.
contract StoxReceiptVaultUnderlyingTest is Test {
    address internal constant OWNER = address(0x0123);

    StoxReceiptVault internal vault;

    function setUp() public {
        // Run the facet constructor at the production address so `_SELF`
        // matches the address the vault's `fallback()` delegatecalls.
        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE
        );
        vault = new OwnedStoxReceiptVault(OWNER);
    }

    function underlying() internal view returns (IStoxUnderlyingV1) {
        return IStoxUnderlyingV1(address(vault));
    }

    /// The ERC-7201 slot is the spec formula over `rain.storage.underlying.1`.
    function testStorageLocation() external pure {
        assertEq(
            UNDERLYING_STORAGE_LOCATION,
            keccak256(abi.encode(uint256(keccak256("rain.storage.underlying.1")) - 1)) & ~bytes32(uint256(0xff))
        );
        assertEq(UNDERLYING_STORAGE_LOCATION, 0xc5c1ed5563e8e77e516055b037edac16f1d2acbaba4a5d944a7dc6677225a100);
    }

    /// Storage layout pin: `symbol` at the namespace root, `name` at root + 1.
    /// Short strings are stored inline, left-aligned, with `length * 2` in the
    /// low byte.
    function testStorageLayoutPin() external {
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA");
        assertEq(
            vm.load(address(vault), UNDERLYING_STORAGE_LOCATION),
            bytes32(0x4e56444100000000000000000000000000000000000000000000000000000008)
        );
        assertEq(
            vm.load(address(vault), bytes32(uint256(UNDERLYING_STORAGE_LOCATION) + 1)),
            bytes32(0x4e5649444941000000000000000000000000000000000000000000000000000c)
        );
    }

    /// Both getters return the empty string before anything is set.
    function testGettersUnset() external view {
        assertEq(underlying().underlyingSymbol(), "");
        assertEq(underlying().underlyingName(), "");
    }

    /// With nothing set, `symbol()` / `name()` return the stored ERC-20
    /// values, which are empty on a bare vault.
    function testSymbolAndNameUnsetFallBackToStoredValues() external view {
        assertEq(vault.symbol(), "");
        assertEq(vault.name(), "");
    }

    /// The owner sets both values; the getters return them verbatim.
    function testSetUnderlyingStoresValues() external {
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation");
        assertEq(underlying().underlyingSymbol(), "NVDA");
        assertEq(underlying().underlyingName(), "NVIDIA Corporation");
    }

    /// Once set, the vault symbol is "t" + ticker and the name is the
    /// underlying name + " (ST0x)".
    function testSymbolAndNameDerivedFromUnderlying() external {
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation");
        assertEq(vault.symbol(), "tNVDA");
        assertEq(vault.name(), "NVIDIA Corporation (ST0x)");
    }

    /// The derivation holds for any non-empty values.
    function testSymbolAndNameDerivedFromUnderlyingFuzz(string memory newSymbol, string memory newName) external {
        vm.assume(bytes(newSymbol).length > 0 && bytes(newName).length > 0);
        vm.prank(OWNER);
        underlying().setUnderlying(newSymbol, newName);
        assertEq(vault.symbol(), string.concat("t", newSymbol));
        assertEq(vault.name(), string.concat(newName, ST0X_NAME_SUFFIX));
    }

    /// The first set emits the empty old values alongside the new ones.
    function testSetUnderlyingEmitsEvent() external {
        vm.expectEmit(address(vault));
        emit IStoxUnderlyingV1.UnderlyingSet(OWNER, "", "", "NVDA", "NVIDIA Corporation");
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation");
    }

    /// The values are not write-once: a later set replaces both, reports the
    /// previous values in the event, and moves the derived metadata with it.
    function testSetUnderlyingOverwrites() external {
        vm.prank(OWNER);
        underlying().setUnderlying("FB", "Meta Platforms, Inc.");

        vm.expectEmit(address(vault));
        emit IStoxUnderlyingV1.UnderlyingSet(OWNER, "FB", "Meta Platforms, Inc.", "META", "Meta Platforms Inc");
        vm.prank(OWNER);
        underlying().setUnderlying("META", "Meta Platforms Inc");

        assertEq(underlying().underlyingSymbol(), "META");
        assertEq(underlying().underlyingName(), "Meta Platforms Inc");
        assertEq(vault.symbol(), "tMETA");
        assertEq(vault.name(), "Meta Platforms Inc (ST0x)");
    }

    /// Anyone other than the owner is rejected with OZ's ownership error.
    function testSetUnderlyingNonOwnerReverts(address caller) external {
        vm.assume(caller != OWNER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation");
    }

    /// An empty symbol is rejected.
    function testSetUnderlyingEmptySymbolReverts() external {
        vm.expectRevert(EmptyUnderlyingSymbol.selector);
        vm.prank(OWNER);
        underlying().setUnderlying("", "NVIDIA Corporation");
    }

    /// An empty name is rejected.
    function testSetUnderlyingEmptyNameReverts() external {
        vm.expectRevert(EmptyUnderlyingName.selector);
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "");
    }

    /// The ownership check runs before the emptiness checks, so a non-owner
    /// learns nothing from the revert about which input was bad.
    function testSetUnderlyingNonOwnerEmptyRevertsUnauthorized() external {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        underlying().setUnderlying("", "");
    }

    /// A rejected set leaves the stored values untouched.
    function testRejectedSetLeavesValuesUntouched() external {
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation");
        vm.expectRevert(EmptyUnderlyingName.selector);
        vm.prank(OWNER);
        underlying().setUnderlying("AAPL", "");
        assertEq(vault.symbol(), "tNVDA");
        assertEq(vault.name(), "NVIDIA Corporation (ST0x)");
    }

    /// With no facet code at the pinned address the self-call returns nothing,
    /// and `symbol()` / `name()` revert rather than reading stale memory.
    function testSymbolAndNameRevertWithoutFacet() external {
        vm.etch(LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, "");
        vm.expectRevert(bytes(""));
        vault.symbol();
        vm.expectRevert(bytes(""));
        vault.name();
    }

    /// Every new facet entry point refuses to run outside a delegatecall.
    function testFacetDirectCallsRevert() external {
        StoxCorporateActionsFacet facet =
            StoxCorporateActionsFacet(LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE);
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        facet.underlyingSymbol();
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        facet.underlyingName();
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        facet.receiptVaultSymbol();
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        facet.receiptVaultName();
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        facet.setUnderlying("NVDA", "NVIDIA Corporation");
    }

    /// The vault's `symbol()` / `name()` are answered by the facet views of
    /// the same values, reachable directly through the vault's fallback.
    function testFacetMetadataViewsRouteThroughFallback() external {
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation");
        assertEq(StoxCorporateActionsFacet(address(vault)).receiptVaultSymbol(), vault.symbol());
        assertEq(StoxCorporateActionsFacet(address(vault)).receiptVaultName(), vault.name());
    }
}
