// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {
    OffchainAssetReceiptVaultConfigV2
} from "rain-vats-0.2.5/src/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {ReceiptVaultConfigV2} from "rain-vats-0.2.5/src/abstract/ReceiptVault.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.5/src/interface/IReceiptVaultV3.sol";
import {IReceiptV3} from "rain-vats-0.2.5/src/interface/IReceiptV3.sol";
import {StoxUnifiedDeployer} from "../../../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {IStoxUnderlyingV1} from "../../../src/interface/IStoxUnderlyingV1.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

/// End-to-end naming for a token pair deployed through the real Zoltu stack:
/// the tStock and its wrapper fall back to the initialized metadata until the
/// owner sets the underlying ticker and name, then both derive from it.
contract StoxUnderlyingIntegrationTest is Test {
    StoxReceiptVault internal vault;
    StoxWrappedTokenVault internal wrapper;

    function setUp() public {
        LibTestDeploy.deployAll(vm);

        OffchainAssetReceiptVaultConfigV2 memory config = OffchainAssetReceiptVaultConfigV2({
            initialAdmin: address(this),
            receiptVaultConfig: ReceiptVaultConfigV2({
                asset: address(0), name: "NVIDIA Corporation ST0x", symbol: "tNVDA", receipt: address(0)
            })
        });

        vm.recordLogs();
        StoxUnifiedDeployer(LibProdDeployV4.STOX_UNIFIED_DEPLOYER_CANDIDATE).newTokenAndWrapperVault(config);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == LibProdDeployV4.STOX_UNIFIED_DEPLOYER_CANDIDATE) {
                (, address receiptVault, address wrapperVault) = abi.decode(logs[i].data, (address, address, address));
                vault = StoxReceiptVault(payable(receiptVault));
                wrapper = StoxWrappedTokenVault(wrapperVault);
            }
        }
        require(address(vault) != address(0), "deployment not found");
    }

    /// Unset: the tStock reports its initialized metadata and the wrapper
    /// derives "Wrapped " / "w" from it.
    function testUnsetFallbacks() external view {
        assertEq(IStoxUnderlyingV1(address(vault)).underlyingSymbol(), "");
        assertEq(IStoxUnderlyingV1(address(vault)).underlyingName(), "");
        assertEq(vault.symbol(), "tNVDA");
        assertEq(vault.name(), "NVIDIA Corporation ST0x");
        assertEq(wrapper.symbol(), "wtNVDA");
        assertEq(wrapper.name(), "Wrapped NVIDIA Corporation ST0x");
    }

    /// Set: both tokens derive from the underlying ticker and name.
    function testDerivedFromUnderlying() external {
        IStoxUnderlyingV1(address(vault)).setUnderlying("NVDA", "NVIDIA Corporation");
        assertEq(vault.symbol(), "tNVDA");
        assertEq(vault.name(), "NVIDIA Corporation (ST0x)");
        assertEq(wrapper.symbol(), "NVDAs");
        assertEq(wrapper.name(), "NVIDIA Corporation (ST0x)");
    }

    /// With no facet code at the pinned address, both tokens keep the
    /// metadata stored at initialization rather than reverting, even if the
    /// underlying was set earlier.
    function testNoFacetFallsBackToStoredMetadata() external {
        IStoxUnderlyingV1(address(vault)).setUnderlying("NVDA", "NVIDIA Corporation");
        vm.etch(LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, "");
        assertEq(vault.symbol(), "tNVDA");
        assertEq(vault.name(), "NVIDIA Corporation ST0x");
        assertEq(wrapper.symbol(), "wtNVDA");
        assertEq(wrapper.name(), "Wrapped NVIDIA Corporation ST0x");
    }

    /// A facet answer shorter than a string head, or a reverting facet,
    /// also falls back to the stored metadata.
    function testShortOrRevertingFacetFallsBackToStoredMetadata() external {
        IStoxUnderlyingV1(address(vault)).setUnderlying("NVDA", "NVIDIA Corporation");
        // PUSH1 0x20 PUSH1 0x00 RETURN: one zero word.
        vm.etch(LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, hex"60206000f3");
        assertEq(vault.symbol(), "tNVDA");
        assertEq(vault.name(), "NVIDIA Corporation ST0x");
        // PUSH1 0x00 PUSH1 0x00 REVERT.
        vm.etch(LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, hex"60006000fd");
        assertEq(vault.symbol(), "tNVDA");
        assertEq(vault.name(), "NVIDIA Corporation ST0x");
    }

    /// The ERC-1155 receipt builds its name and symbol from the vault's
    /// `symbol()`, which reads "t" + ticker either way.
    function testReceiptFollowsVaultSymbol() external {
        IReceiptV3 receipt = IReceiptV3(address(IReceiptVaultV3(payable(address(vault))).receipt()));
        string memory receiptSymbolBefore = receipt.symbol();
        string memory receiptNameBefore = receipt.name();
        IStoxUnderlyingV1(address(vault)).setUnderlying("NVDA", "NVIDIA Corporation");
        assertEq(receipt.symbol(), receiptSymbolBefore);
        assertEq(receipt.name(), receiptNameBefore);
    }

    /// A ticker change moves both tokens' metadata with it.
    function testRenameFollowsThrough() external {
        IStoxUnderlyingV1(address(vault)).setUnderlying("FB", "Meta Platforms, Inc.");
        assertEq(wrapper.symbol(), "FBs");
        IStoxUnderlyingV1(address(vault)).setUnderlying("META", "Meta Platforms, Inc.");
        assertEq(vault.symbol(), "tMETA");
        assertEq(wrapper.symbol(), "METAs");
        assertEq(wrapper.name(), "Meta Platforms, Inc. (ST0x)");
    }
}
