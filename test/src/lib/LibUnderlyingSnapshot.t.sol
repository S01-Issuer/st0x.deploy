// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyParams
} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {LibUnderlyingSnapshot} from "../../../src/lib/LibUnderlyingSnapshot.sol";
import {LibProdTokenConfig, TokenConfig, UNDERLYING_SNAPSHOT_AS_OF} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenParams} from "../../../src/lib/LibProdTokenParams.sol";
import {
    LibUnderlyingSnapshotCode,
    UNDERLYING_SNAPSHOT_ROOT
} from "../../../src/generated/LibUnderlyingSnapshotCode.sol";
import {
    LibUnderlyingSnapshotBuilder,
    UnderlyingSnapshotRow
} from "../../../script/lib/LibUnderlyingSnapshotBuilder.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

contract LibUnderlyingSnapshotTest is Test {
    function productionTokens() internal pure returns (address[] memory, TokenConfig[] memory) {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        RegistryBeaconProxyParams[] memory params = LibProdTokenParams.tokenParams(configs);
        address[] memory tokens = new address[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            tokens[i] = LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(params[i]);
        }
        return (tokens, configs);
    }

    function deploy(uint256 asOf, UnderlyingSnapshotRow[] memory rows) internal returns (address, uint256) {
        LibRainDeploy.etchZoltuFactory(vm);
        (bytes memory rootCode, bytes[] memory shardCodes) = LibUnderlyingSnapshotBuilder.build(asOf, rows);
        for (uint256 i = 0; i < shardCodes.length; i++) {
            if (LibRainDeploy.zoltuAddress(shardCodes[i]).code.length == 0) LibRainDeploy.deployZoltu(shardCodes[i]);
        }
        address root = LibRainDeploy.zoltuAddress(rootCode);
        if (root.code.length == 0) LibRainDeploy.deployZoltu(rootCode);
        return (root, shardCodes.length);
    }

    /// The deployed generated snapshot holds every production token's current
    /// ticker, name and ISIN under its address.
    function testEveryProductionTokenReadsItsRow() external {
        LibTestDeploy.deployUnderlyingSnapshot(vm);
        (address[] memory tokens, TokenConfig[] memory configs) = productionTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            LibUnderlyingSnapshot.Lookup memory row = LibUnderlyingSnapshot.lookup(UNDERLYING_SNAPSHOT_ROOT, tokens[i]);
            assertEq(row.asOf, UNDERLYING_SNAPSHOT_AS_OF, "asOf");
            assertTrue(row.found, configs[i].ticker);
            assertEq(row.ticker, configs[i].ticker, "ticker");
            assertEq(row.name, configs[i].underlyingName, "name");
            assertEq(row.isin, configs[i].isin, "isin");
        }
    }

    /// The generated root and shards are what the builder makes from the
    /// production table today.
    function testGeneratedSnapshotMatchesTheProductionTable() external {
        (address[] memory tokens, TokenConfig[] memory configs) = productionTokens();
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            rows[i] = UnderlyingSnapshotRow(tokens[i], configs[i].ticker, configs[i].underlyingName, configs[i].isin);
        }
        (bytes memory rootCode, bytes[] memory shardCodes) =
            LibUnderlyingSnapshotBuilder.build(UNDERLYING_SNAPSHOT_AS_OF, rows);
        assertEq(rootCode, LibUnderlyingSnapshotCode.ROOT_CREATION_CODE, "root");
        bytes[] memory generated = LibUnderlyingSnapshotCode.shardCreationCodes();
        assertEq(shardCodes.length, generated.length, "shard count");
        for (uint256 i = 0; i < shardCodes.length; i++) {
            assertEq(shardCodes[i], generated[i], "shard");
        }
        assertEq(LibRainDeploy.zoltuAddress(rootCode), UNDERLYING_SNAPSHOT_ROOT, "root address");
    }

    function testNonMemberIsNotFound(address token) external {
        LibTestDeploy.deployUnderlyingSnapshot(vm);
        (address[] memory tokens,) = productionTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            vm.assume(token != tokens[i]);
        }
        LibUnderlyingSnapshot.Lookup memory row = LibUnderlyingSnapshot.lookup(UNDERLYING_SNAPSHOT_ROOT, token);
        assertEq(row.asOf, UNDERLYING_SNAPSHOT_AS_OF, "asOf");
        assertFalse(row.found, "found");
        assertEq(row.ticker, "", "ticker");
        assertEq(row.name, "", "name");
        assertEq(row.isin, "", "isin");
    }

    function rowsFrom(bytes32 seed, uint256 n) internal pure returns (UnderlyingSnapshotRow[] memory) {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](n);
        for (uint256 i = 0; i < n; i++) {
            bytes32 h = keccak256(abi.encode(seed, i));
            rows[i] = UnderlyingSnapshotRow(
                address(uint160(uint256(h))),
                vm.toString(uint256(uint16(uint256(h)))),
                string.concat("Name ", vm.toString(h)),
                vm.toString(uint256(uint40(uint256(h))))
            );
        }
        return rows;
    }

    function assertRoundTrips(uint256 asOf, bytes32 seed, UnderlyingSnapshotRow[] memory rows) internal returns (uint256) {
        (address root, uint256 shardCount) = deploy(asOf, rows);
        for (uint256 i = 0; i < rows.length; i++) {
            LibUnderlyingSnapshot.Lookup memory row = LibUnderlyingSnapshot.lookup(root, rows[i].token);
            assertEq(row.asOf, asOf, "asOf");
            assertTrue(row.found, "found");
            assertEq(row.ticker, rows[i].ticker, "ticker");
            assertEq(row.name, rows[i].name, "name");
            assertEq(row.isin, rows[i].isin, "isin");
        }
        address outsider = address(uint160(uint256(keccak256(abi.encode(seed, "outsider")))));
        assertFalse(LibUnderlyingSnapshot.lookup(root, outsider).found, "outsider");
        return shardCount;
    }

    function testBuiltRowsRoundTrip(uint256 asOf, bytes32 seed, uint8 count) external {
        assertRoundTrips(asOf, seed, rowsFrom(seed, bound(count, 1, 40)));
    }

    /// Too many rows for one shard still read back, from several shards.
    function testManyBuiltRowsRoundTripAcrossShards() external {
        bytes32 seed = keccak256("many rows");
        assertGt(assertRoundTrips(UNDERLYING_SNAPSHOT_AS_OF, seed, rowsFrom(seed, 600)), 1, "shard count");
    }
}
