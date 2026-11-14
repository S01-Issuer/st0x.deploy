// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.7.0/proxy/beacon/BeaconProxy.sol";
import {IAuthorizeV1} from "rain-vats-0.2.20/src/interface/IAuthorizeV1.sol";
import {
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
    OffchainAssetReceiptVaultConfigV3
} from "rain-vats-0.2.20/src/interface/IOffchainAssetReceiptVaultV1.sol";
import {CloneFactory} from "rain-factory-deploy-0.2.8/src/concrete/CloneFactory.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {IStoxUnderlyingV2} from "../../../src/interface/IStoxUnderlyingV2.sol";
import {MalformedUnderlyingSnapshot} from "../../../src/error/ErrUnderlying.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {UNDERLYING_SNAPSHOT_ROOT} from "../../../src/generated/LibUnderlyingSnapshotCode.sol";
import {
    LibUnderlyingSnapshotBuilder,
    UnderlyingSnapshotRow
} from "../../../script/lib/LibUnderlyingSnapshotBuilder.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LegacyInitStoxReceiptVault} from "./LegacyInitStoxReceiptVault.sol";

/// Which of the override, the snapshot row and the listing values every name,
/// ticker and ISIN read resolves to, for vaults behind the real beacon proxy.
contract StoxCorporateActionsFacetUnderlyingReadRuleTest is Test {
    address internal constant AUTHORITY = address(uint160(uint256(keccak256("AUTHORITY"))));
    bytes32 internal constant RBAC_NAME = keccak256("st0x.rbac.test.v1");
    uint256 internal constant AS_OF = 1_000_000;

    string internal constant LISTING_TICKER = "NVDA";
    string internal constant LISTING_NAME = "NVIDIA Corporation";
    string internal constant LISTING_ISIN = "US67066G1040";
    string internal constant ROW_TICKER = "NVDX";
    string internal constant ROW_NAME = "NVIDIA Holdings";
    string internal constant ROW_ISIN = "US0378331005";
    string internal constant OVERRIDE_TICKER = "NVDO";
    string internal constant OVERRIDE_NAME = "NVIDIA Overridden";
    string internal constant OVERRIDE_ISIN = "US30303M1027";

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
            AUTHORITY, LibTestDeploy.vaultData(LISTING_ISIN, LISTING_TICKER, LISTING_NAME, AUTHORITY, RBAC_NAME)
        );
        sWrapper = LibTestDeploy.newWrapper(AUTHORITY, address(sVault));
    }

    /// A vault initialized from V3 data before the beacon moved to the
    /// current implementation.
    function newLegacyVault() internal returns (StoxReceiptVault) {
        address beacon = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;
        address owner = UpgradeableBeacon(beacon).owner();
        address legacyImplementation = address(new LegacyInitStoxReceiptVault());
        vm.prank(owner);
        UpgradeableBeacon(beacon).upgradeTo(legacyImplementation);
        LegacyInitStoxReceiptVault legacy = LegacyInitStoxReceiptVault(payable(address(new BeaconProxy(beacon, ""))));
        legacy.initializeLegacy(
            abi.encode(
                OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
                OffchainAssetReceiptVaultConfigV3({
                    name: "NVIDIA Corporation ST0x",
                    symbol: "tNVDA",
                    authority: AUTHORITY,
                    rbacName: RBAC_NAME,
                    receiptBeaconName: LibStoxConfig.RECEIPT_BEACON_NAME,
                    metadata: ""
                })
            )
        );
        vm.prank(owner);
        UpgradeableBeacon(beacon).upgradeTo(LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE);
        return StoxReceiptVault(payable(address(legacy)));
    }

    /// Replaces the snapshot at its constant address with one holding `rows`.
    function plantSnapshot(uint256 asOf, UnderlyingSnapshotRow[] memory rows) internal {
        (bytes memory rootCode, bytes[] memory shardCodes) = LibUnderlyingSnapshotBuilder.build(asOf, rows);
        for (uint256 i = 0; i < shardCodes.length; i++) {
            if (LibRainDeploy.zoltuAddress(shardCodes[i]).code.length == 0) LibRainDeploy.deployZoltu(shardCodes[i]);
        }
        address root = LibRainDeploy.zoltuAddress(rootCode);
        if (root.code.length == 0) LibRainDeploy.deployZoltu(rootCode);
        vm.etch(UNDERLYING_SNAPSHOT_ROOT, root.code);
    }

    /// A snapshot with a row for `token` among rows for other tokens.
    function plantSnapshotWithRow(uint256 asOf, address token) internal {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](3);
        rows[0] = UnderlyingSnapshotRow(address(0x1111), "AAA", "Other One", "US5949181045");
        rows[1] = UnderlyingSnapshotRow(token, ROW_TICKER, ROW_NAME, ROW_ISIN);
        rows[2] = UnderlyingSnapshotRow(address(0x2222), "BBB", "Other Two", "US5949181045");
        plantSnapshot(asOf, rows);
    }

    function plantSnapshotWithoutRow(uint256 asOf) internal {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](1);
        rows[0] = UnderlyingSnapshotRow(address(0x1111), "AAA", "Other One", "US5949181045");
        plantSnapshot(asOf, rows);
    }

    function setOverrideAt(StoxReceiptVault vault, uint256 timestamp) internal {
        vm.warp(timestamp);
        IStoxUnderlyingV2(address(vault)).setUnderlying(OVERRIDE_TICKER, OVERRIDE_NAME, OVERRIDE_ISIN);
    }

    function assertResolves(StoxReceiptVault vault, string memory ticker, string memory name, string memory isin)
        internal
        view
    {
        assertEq(IStoxUnderlyingV2(address(vault)).underlyingSymbol(), ticker, "underlyingSymbol");
        assertEq(IStoxUnderlyingV2(address(vault)).underlyingName(), name, "underlyingName");
        assertEq(IStoxUnderlyingV2(address(vault)).underlyingIsin(), isin, "underlyingIsin");
        assertEq(vault.symbol(), string.concat("t", ticker), "symbol");
        assertEq(vault.name(), string.concat(name, " (ST0x)"), "name");
    }

    function assertResolvesToOverride(StoxReceiptVault vault) internal view {
        assertResolves(vault, OVERRIDE_TICKER, OVERRIDE_NAME, OVERRIDE_ISIN);
    }

    function assertResolvesToRow(StoxReceiptVault vault) internal view {
        assertResolves(vault, ROW_TICKER, ROW_NAME, ROW_ISIN);
    }

    function assertResolvesToListing(StoxReceiptVault vault) internal view {
        assertResolves(vault, LISTING_TICKER, LISTING_NAME, LISTING_ISIN);
    }

    function assertEveryReadReverts(StoxReceiptVault vault) internal {
        bytes memory err = abi.encodeWithSelector(MalformedUnderlyingSnapshot.selector, UNDERLYING_SNAPSHOT_ROOT);
        vm.expectRevert(err);
        IStoxUnderlyingV2(address(vault)).underlyingSymbol();
        vm.expectRevert(err);
        IStoxUnderlyingV2(address(vault)).underlyingName();
        vm.expectRevert(err);
        IStoxUnderlyingV2(address(vault)).underlyingIsin();
        vm.expectRevert(err);
        vault.symbol();
        vm.expectRevert(err);
        vault.name();
    }

    function testEveryReadRevertsWithoutSnapshotRoot() external {
        vm.etch(UNDERLYING_SNAPSHOT_ROOT, "");
        assertEveryReadReverts(sVault);
    }

    /// Even an override needs the snapshot's `asOf` to be compared against.
    function testOverrideStillRevertsWithoutSnapshotRoot() external {
        setOverrideAt(sVault, type(uint64).max);
        vm.etch(UNDERLYING_SNAPSHOT_ROOT, "");
        assertEveryReadReverts(sVault);
    }

    function testLegacyVaultReadsRevertWithoutSnapshotRoot() external {
        StoxReceiptVault legacy = newLegacyVault();
        vm.etch(UNDERLYING_SNAPSHOT_ROOT, "");
        assertEveryReadReverts(legacy);
    }

    function testNoOverrideNoRowReadsListingValues() external {
        plantSnapshotWithoutRow(AS_OF);
        assertResolvesToListing(sVault);
        assertEq(sWrapper.symbol(), "NVDAs");
        assertEq(sWrapper.name(), "NVIDIA Corporation (ST0x)");
    }

    function testNoOverrideReadsSnapshotRow() external {
        plantSnapshotWithRow(AS_OF, address(sVault));
        assertResolvesToRow(sVault);
        assertEq(sWrapper.symbol(), "NVDXs");
        assertEq(sWrapper.name(), "NVIDIA Holdings (ST0x)");
    }

    function testOverrideNewerThanAsOfBeatsRow() external {
        plantSnapshotWithRow(AS_OF, address(sVault));
        setOverrideAt(sVault, AS_OF + 1);
        assertResolvesToOverride(sVault);
        assertEq(sWrapper.symbol(), "NVDOs");
        assertEq(sWrapper.name(), "NVIDIA Overridden (ST0x)");
    }

    /// A tie goes to the snapshot.
    function testOverrideAtAsOfLosesToRow() external {
        plantSnapshotWithRow(AS_OF, address(sVault));
        setOverrideAt(sVault, AS_OF);
        assertResolvesToRow(sVault);
    }

    function testOverrideOlderThanAsOfLosesToRow(uint256 timestamp) external {
        timestamp = bound(timestamp, 1, AS_OF);
        plantSnapshotWithRow(AS_OF, address(sVault));
        setOverrideAt(sVault, timestamp);
        assertResolvesToRow(sVault);
    }

    /// A newer snapshot cut after the override takes the row back.
    function testNewerSnapshotTakesRowBackFromOverride() external {
        plantSnapshotWithRow(AS_OF, address(sVault));
        setOverrideAt(sVault, AS_OF + 1);
        assertResolvesToOverride(sVault);
        plantSnapshotWithRow(AS_OF + 1, address(sVault));
        assertResolvesToRow(sVault);
    }

    /// With no row to compete with, an override applies at any age.
    function testOverrideWithoutRowAppliesAtAnyAge(uint256 timestamp) external {
        timestamp = bound(timestamp, 1, type(uint64).max);
        plantSnapshotWithoutRow(AS_OF);
        setOverrideAt(sVault, timestamp);
        assertResolvesToOverride(sVault);
    }

    /// The rule as one oracle over every combination of override, row and age.
    function testReadRuleMatchesOracle(bool hasOverride, bool hasRow, uint256 asOf, uint256 timestamp) external {
        asOf = bound(asOf, 0, type(uint64).max);
        timestamp = bound(timestamp, 1, type(uint64).max);
        if (hasRow) {
            plantSnapshotWithRow(asOf, address(sVault));
        } else {
            plantSnapshotWithoutRow(asOf);
        }
        if (hasOverride) setOverrideAt(sVault, timestamp);

        if (hasOverride && (timestamp > asOf || !hasRow)) {
            assertResolvesToOverride(sVault);
        } else if (hasRow) {
            assertResolvesToRow(sVault);
        } else {
            assertResolvesToListing(sVault);
        }
    }

    function testLegacyVaultWithoutOverrideKeepsItsStoredNames() external {
        StoxReceiptVault legacy = newLegacyVault();
        StoxWrappedTokenVault legacyWrapper = LibTestDeploy.newWrapper(AUTHORITY, address(legacy));
        assertEq(IStoxUnderlyingV2(address(legacy)).underlyingSymbol(), "");
        assertEq(IStoxUnderlyingV2(address(legacy)).underlyingName(), "");
        assertEq(IStoxUnderlyingV2(address(legacy)).underlyingIsin(), "");
        assertEq(legacy.symbol(), "tNVDA");
        assertEq(legacy.name(), "NVIDIA Corporation ST0x");
        assertEq(legacyWrapper.symbol(), "wtNVDA");
        assertEq(legacyWrapper.name(), "Wrapped NVIDIA Corporation ST0x");
    }

    function testLegacyVaultOverrideApplies(uint256 timestamp) external {
        timestamp = bound(timestamp, 1, type(uint64).max);
        StoxReceiptVault legacy = newLegacyVault();
        StoxWrappedTokenVault legacyWrapper = LibTestDeploy.newWrapper(AUTHORITY, address(legacy));
        setOverrideAt(legacy, timestamp);
        assertResolvesToOverride(legacy);
        assertEq(legacyWrapper.symbol(), "NVDOs");
        assertEq(legacyWrapper.name(), "NVIDIA Overridden (ST0x)");
    }
}
