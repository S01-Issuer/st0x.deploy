// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAuthorizeV1} from "rain-vats-0.2.25/src/interface/IAuthorizeV1.sol";
import {CloneFactory} from "rain-factory-deploy-0.2.14/src/concrete/CloneFactory.sol";
import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {IStoxAssetIdV1} from "../../../src/interface/IStoxAssetIdV1.sol";
import {IStoxUnderlyingV2} from "../../../src/interface/IStoxUnderlyingV2.sol";
import {MalformedUnderlyingSnapshot} from "../../../src/error/ErrUnderlying.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {UNDERLYING_SNAPSHOT_ROOT} from "../../../src/generated/LibUnderlyingSnapshotCode.sol";
import {LibUnderlyingSnapshotBuilder, UnderlyingSnapshotRow} from "../../../script/LibUnderlyingSnapshotBuilder.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

/// `assetId()` reads the current ISIN by the snapshot read rule.
contract StoxReceiptVaultAssetIdTest is Test {
    address internal constant AUTHORITY = address(uint160(uint256(keccak256("AUTHORITY"))));
    address internal constant OWNER = address(uint160(uint256(keccak256("OWNER"))));
    bytes32 internal constant RBAC_NAME = keccak256("st0x.rbac.test.v1");
    uint256 internal constant AS_OF = 1_000_000;

    string internal constant INIT_ISIN = "US67066G1040";
    string internal constant ROW_ISIN = "US0378331005";
    string internal constant OVERRIDE_ISIN = "US30303M1027";

    StoxReceiptVault internal sVault;

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
        sVault = newVault(INIT_ISIN, "NVDA", "NVIDIA Corporation");
    }

    function newVault(string memory assetId, string memory listingTicker, string memory listingName)
        internal
        returns (StoxReceiptVault)
    {
        return LibTestDeploy.newVault(
            AUTHORITY, LibTestDeploy.vaultData(assetId, listingTicker, listingName, AUTHORITY, RBAC_NAME)
        );
    }

    function assetIdOf(StoxReceiptVault vault) internal view returns (string memory) {
        return IStoxAssetIdV1(address(vault)).assetId();
    }

    /// Replaces the snapshot at its constant address with one holding
    /// `rows`, returning the shard addresses.
    function plantSnapshot(uint256 asOf, UnderlyingSnapshotRow[] memory rows) internal returns (address[] memory) {
        (bytes memory rootCode, bytes[] memory shardCodes) = LibUnderlyingSnapshotBuilder.build(asOf, rows);
        vm.etch(UNDERLYING_SNAPSHOT_ROOT, LibTestDeploy.deployUnderlyingSnapshot(vm, rootCode, shardCodes).code);
        address[] memory shards = new address[](shardCodes.length);
        for (uint256 i = 0; i < shardCodes.length; i++) {
            shards[i] = LibRainDeploy.zoltuAddress(shardCodes[i]);
        }
        return shards;
    }

    function plantSnapshotWithRow(uint256 asOf) internal returns (address[] memory) {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](1);
        rows[0] = UnderlyingSnapshotRow(address(sVault), "NVDX", "NVIDIA Holdings", ROW_ISIN);
        return plantSnapshot(asOf, rows);
    }

    function plantSnapshotWithoutRow(uint256 asOf) internal {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](1);
        rows[0] = UnderlyingSnapshotRow(address(0x1111), "AAA", "Other One", "US5949181045");
        plantSnapshot(asOf, rows);
    }

    function setOverrideAt(uint256 timestamp) internal {
        vm.warp(timestamp);
        vm.prank(OWNER);
        IStoxUnderlyingV2(address(sVault)).setUnderlying("NVDO", "NVIDIA Overridden", OVERRIDE_ISIN);
    }

    function testNoRowNoOverrideReadsTheInitializedAssetId() external {
        StoxReceiptVault aapl = newVault("US0378331005", "AAPL", "Apple Inc.");
        plantSnapshotWithoutRow(AS_OF);
        assertEq(assetIdOf(sVault), INIT_ISIN);
        assertEq(assetIdOf(aapl), "US0378331005");
    }

    function testRowWithoutOverrideWinsOverTheInitializedAssetId() external {
        plantSnapshotWithRow(AS_OF);
        assertEq(assetIdOf(sVault), ROW_ISIN);
    }

    /// A tie goes to the snapshot.
    function testRowWinsOverAnOverrideNoNewerThanAsOf(uint256 timestamp) external {
        timestamp = bound(timestamp, 1, AS_OF);
        plantSnapshotWithRow(AS_OF);
        setOverrideAt(timestamp);
        assertEq(assetIdOf(sVault), ROW_ISIN);
    }

    function testOverrideNewerThanAsOfWinsOverTheRow(uint256 timestamp) external {
        timestamp = bound(timestamp, AS_OF + 1, type(uint64).max);
        plantSnapshotWithRow(AS_OF);
        setOverrideAt(timestamp);
        assertEq(assetIdOf(sVault), OVERRIDE_ISIN);
    }

    function testOverrideWithoutRowWinsAtAnyAge(uint256 timestamp) external {
        timestamp = bound(timestamp, 1, type(uint64).max);
        plantSnapshotWithoutRow(AS_OF);
        setOverrideAt(timestamp);
        assertEq(assetIdOf(sVault), OVERRIDE_ISIN);
    }

    function testMissingRootRevertsLikeName() external {
        vm.etch(UNDERLYING_SNAPSHOT_ROOT, "");
        bytes memory err = abi.encodeWithSelector(MalformedUnderlyingSnapshot.selector, UNDERLYING_SNAPSHOT_ROOT);
        vm.expectRevert(err);
        sVault.name();
        vm.expectRevert(err);
        assetIdOf(sVault);
    }

    function testMissingShardRevertsLikeName() external {
        address[] memory shards = plantSnapshotWithRow(AS_OF);
        assertEq(shards.length, 1);
        vm.etch(shards[0], "");
        bytes memory err = abi.encodeWithSelector(MalformedUnderlyingSnapshot.selector, shards[0]);
        vm.expectRevert(err);
        sVault.name();
        vm.expectRevert(err);
        assetIdOf(sVault);
    }
}
