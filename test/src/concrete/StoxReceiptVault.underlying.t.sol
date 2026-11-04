// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {IStoxUnderlyingV1} from "../../../src/interface/IStoxUnderlyingV1.sol";
import {EmptyUnderlyingSymbol, EmptyUnderlyingName} from "../../../src/error/ErrUnderlying.sol";
import {CorporateActionsFacetNotDeployed} from "../../../src/error/ErrCorporateAction.sol";
import {UNDERLYING_STORAGE_LOCATION, ST0X_NAME_SUFFIX} from "../../../src/lib/LibUnderlying.sol";
import {ERC20_STORAGE_LOCATION} from "../../../src/lib/LibERC20Storage.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {OwnedStoxReceiptVault} from "./OwnedStoxReceiptVault.sol";
import {UnderlyingSetForwarder} from "../../concrete/UnderlyingSetForwarder.sol";

/// Unit tests for the underlying ticker/name surface (`IStoxUnderlyingV1`,
/// implemented by `StoxCorporateActionsFacet`) and the ERC-20 `symbol()` /
/// `name()` that `setUnderlying` writes into the vault's OZ storage. The vault is constructed bare (not initialized),
/// so its stored ERC-20 name and symbol are empty: the unset fallback to
/// initialized values is covered end-to-end in
/// `StoxUnderlyingIntegrationTest`.
contract StoxReceiptVaultUnderlyingTest is Test {
    address internal constant OWNER = address(0x0123);

    StoxReceiptVault internal sVault;

    function setUp() public {
        // Run the facet constructor at the production address so `_SELF`
        // matches the address the vault's `fallback()` delegatecalls.
        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE
        );
        sVault = new OwnedStoxReceiptVault(OWNER);
    }

    function underlying() internal view returns (IStoxUnderlyingV1) {
        return IStoxUnderlyingV1(address(sVault));
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
            vm.load(address(sVault), UNDERLYING_STORAGE_LOCATION),
            bytes32(0x4e56444100000000000000000000000000000000000000000000000000000008)
        );
        assertEq(
            vm.load(address(sVault), bytes32(uint256(UNDERLYING_STORAGE_LOCATION) + 1)),
            bytes32(0x4e5649444941000000000000000000000000000000000000000000000000000c)
        );
    }

    /// `setUnderlying` writes the formatted symbol into OZ's `ERC20Storage`
    /// `_symbol` (root + 4) and the formatted name into `_name` (root + 3),
    /// each into its own slot. Short strings are stored inline, left-aligned,
    /// with `length * 2` in the low byte.
    function testSetUnderlyingWritesOzErc20Slots() external {
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA");
        // "tNVDA"
        assertEq(
            vm.load(address(sVault), bytes32(uint256(ERC20_STORAGE_LOCATION) + 4)),
            bytes32(0x744e56444100000000000000000000000000000000000000000000000000000a)
        );
        // "NVIDIA (ST0x)"
        assertEq(
            vm.load(address(sVault), bytes32(uint256(ERC20_STORAGE_LOCATION) + 3)),
            bytes32(0x4e5649444941202853543078290000000000000000000000000000000000001a)
        );
    }

    /// `symbol()` / `name()` read only OZ's ERC-20 storage: underlying values
    /// written without `setUnderlying` rename nothing.
    function testUnderlyingStorageAloneDoesNotRename() external {
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
        assertEq(underlying().underlyingSymbol(), "NVDA");
        assertEq(sVault.symbol(), "");
        assertEq(sVault.name(), "");
    }

    /// Both getters return the empty string before anything is set.
    function testGettersUnset() external view {
        assertEq(underlying().underlyingSymbol(), "");
        assertEq(underlying().underlyingName(), "");
    }

    /// With nothing set, `symbol()` / `name()` return the stored ERC-20
    /// values, which are empty on a bare vault.
    function testSymbolAndNameUnsetFallBackToStoredValues() external view {
        assertEq(sVault.symbol(), "");
        assertEq(sVault.name(), "");
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
        assertEq(sVault.symbol(), "tNVDA");
        assertEq(sVault.name(), "NVIDIA Corporation (ST0x)");
    }

    /// The derivation holds for any non-empty values.
    function testSymbolAndNameDerivedFromUnderlyingFuzz(string memory newSymbol, string memory newName) external {
        vm.assume(bytes(newSymbol).length > 0 && bytes(newName).length > 0);
        vm.prank(OWNER);
        underlying().setUnderlying(newSymbol, newName);
        assertEq(sVault.symbol(), string.concat("t", newSymbol));
        assertEq(sVault.name(), string.concat(newName, ST0X_NAME_SUFFIX));
    }

    /// The first set emits the empty old values alongside the new ones.
    function testSetUnderlyingEmitsEvent() external {
        vm.expectEmit(address(sVault));
        emit IStoxUnderlyingV1.UnderlyingSet(OWNER, "", "", "NVDA", "NVIDIA Corporation");
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation");
    }

    /// `UnderlyingSet` indexes `sender` and carries the four strings as
    /// data, checked against the raw log rather than the interface's own
    /// event declaration.
    function testUnderlyingSetIndexesSender() external {
        vm.recordLogs();
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(sVault));
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256("UnderlyingSet(address,string,string,string,string)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(OWNER))));
        assertEq(logs[0].data, abi.encode("", "", "NVDA", "NVIDIA Corporation"));
    }

    /// The values are not write-once: a later set replaces both, reports the
    /// previous values in the event, and moves the derived metadata with it.
    function testSetUnderlyingOverwrites() external {
        vm.prank(OWNER);
        underlying().setUnderlying("FB", "Meta Platforms, Inc.");

        vm.expectEmit(address(sVault));
        emit IStoxUnderlyingV1.UnderlyingSet(OWNER, "FB", "Meta Platforms, Inc.", "META", "Meta Platforms Inc");
        vm.prank(OWNER);
        underlying().setUnderlying("META", "Meta Platforms Inc");

        assertEq(underlying().underlyingSymbol(), "META");
        assertEq(underlying().underlyingName(), "Meta Platforms Inc");
        assertEq(sVault.symbol(), "tMETA");
        assertEq(sVault.name(), "Meta Platforms Inc (ST0x)");
    }

    /// Anyone other than the owner is rejected with OZ's ownership error.
    function testSetUnderlyingNonOwnerReverts(address caller) external {
        vm.assume(caller != OWNER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation");
    }

    /// The gate keys on `msg.sender` alone: a call from an intermediate
    /// contract is rejected even when `tx.origin` is the owner, and nothing
    /// is stored.
    function testSetUnderlyingRejectsContractCallerWithOwnerOrigin() external {
        UnderlyingSetForwarder forwarder = new UnderlyingSetForwarder();
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(forwarder))
        );
        vm.prank(OWNER, OWNER);
        forwarder.forward(underlying(), "NVDA", "NVIDIA Corporation");
        assertEq(underlying().underlyingSymbol(), "");
        assertEq(underlying().underlyingName(), "");
    }

    /// Any non-owner `msg.sender` is rejected even when `tx.origin` is the
    /// owner.
    function testSetUnderlyingRejectsNonOwnerSenderWithOwnerOrigin(address caller) external {
        vm.assume(caller != OWNER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller, OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation");
        assertEq(underlying().underlyingSymbol(), "");
        assertEq(underlying().underlyingName(), "");
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
        assertEq(sVault.symbol(), "tNVDA");
        assertEq(sVault.name(), "NVIDIA Corporation (ST0x)");
    }

    /// With no facet code at the pinned address, `setUnderlying` reverts
    /// instead of succeeding as a no-op, and the getters revert too.
    function testFacetCallsRevertWithoutFacet() external {
        address facet = LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE;
        vm.etch(facet, "");
        vm.expectRevert(abi.encodeWithSelector(CorporateActionsFacetNotDeployed.selector, facet));
        vm.prank(OWNER);
        underlying().setUnderlying("NVDA", "NVIDIA Corporation");
        vm.expectRevert(abi.encodeWithSelector(CorporateActionsFacetNotDeployed.selector, facet));
        underlying().underlyingSymbol();
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
        facet.setUnderlying("NVDA", "NVIDIA Corporation");
    }
}
