// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MerkleProof} from "@openzeppelin-contracts-5.7.0/utils/cryptography/MerkleProof.sol";

import {LibProdTokenConfig, Region, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibListing} from "../../../src/lib/LibListing.sol";
import {LibProdTokenParams} from "../../../src/lib/LibProdTokenParams.sol";
import {LibRainDeployRegistryBeaconProxy} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {MalformedUnderlying} from "../../../src/lib/LibUnderlyingNamingRollout.sol";
import {
    LibListingTree,
    ListingDuplicateToken,
    ListingRow,
    ListingRowWithoutAssetId,
    ListingWithoutRows
} from "../../../src/lib/LibListingTree.sol";

/// @title LibListingTreeTest
/// @notice The listing tree is OpenZeppelin's `StandardMerkleTree`: its root and proofs equal the JS library's, every
/// proof verifies, and malformed rows are refused.
contract LibListingTreeTest is Test {
    function goldenRows() internal pure returns (ListingRow[] memory) {
        ListingRow[] memory listed = new ListingRow[](5);
        listed[0] = ListingRow(0x1111111111111111111111111111111111111111, "US67066G1040", "NVDA", "NVIDIA Corporation");
        listed[1] = ListingRow(0x2222222222222222222222222222222222222222, "US0378331005", "AAPL", "Apple Inc.");
        listed[2] =
            ListingRow(0x3333333333333333333333333333333333333333, "US5949181045", "MSFT", "Microsoft Corporation");
        listed[3] = ListingRow(0x4444444444444444444444444444444444444444, "US88160R1014", "TSLA", "Tesla, Inc.");
        listed[4] = ListingRow(0x5555555555555555555555555555555555555555, "US0231351067", "AMZN", "Amazon.com, Inc.");
        return listed;
    }

    /// Root and proofs equal `StandardMerkleTree.of(rows, ["address","string","string","string"])` of
    /// the OpenZeppelin merkle-tree JS library 1.0.8 (node 22) over the same five rows.
    function testGoldenVector() external pure {
        ListingRow[] memory listed = goldenRows();
        assertEq(
            LibListingTree.root(listed), 0x136cef67c2bac7f4748d75ab639e8b34c6b3e45a400552d1801566ec41219374, "root"
        );
        bytes32[] memory proof0 = LibListingTree.proof(listed, 0);
        assertEq(proof0.length, 2, "proof 0 length");
        assertEq(proof0[0], 0xba7a46ddd7e2c9d1668b0d0296064735c467bce2a596a470c56d0b54bef691ed, "proof 0[0]");
        assertEq(proof0[1], 0x781220580fe1fea8be58db5844a0a8677c19c43b2c3bc52cc1d7bf73ab0438c1, "proof 0[1]");
        bytes32[] memory proof2 = LibListingTree.proof(listed, 2);
        assertEq(proof2.length, 3, "proof 2 length");
        assertEq(proof2[0], 0x6f51c546e7437422cdfbfe499142c7fc90a57e5d478da2cc281c03824dcc6304, "proof 2[0]");
        assertEq(proof2[1], 0xf68b8549f625e7f80e66f4d8530ded82aa82c67cefd721d8a638b8ed445f280a, "proof 2[1]");
        assertEq(proof2[2], 0x781220580fe1fea8be58db5844a0a8677c19c43b2c3bc52cc1d7bf73ab0438c1, "proof 2[2]");
        bytes32[] memory proof4 = LibListingTree.proof(listed, 4);
        assertEq(proof4.length, 3, "proof 4 length");
        assertEq(proof4[0], 0xcf33144b8c59f48d830f3550d917d5499a88896d9ffe2543eb3114a537ab1545, "proof 4[0]");
    }

    /// Every row's proof verifies against the root with OpenZeppelin's `MerkleProof`, at any tree size.
    function testEveryProofVerifies(uint8 size) external pure {
        uint256 count = bound(size, 1, 64);
        ListingRow[] memory listed = new ListingRow[](count);
        for (uint256 i = 0; i < count; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            listed[i] = ListingRow(address(uint160(i + 1)), vm.toString(i), "T", "Name");
        }
        bytes32 root = LibListingTree.root(listed);
        for (uint256 i = 0; i < count; i++) {
            bytes32 leaf = LibListing.leaf(listed[i].token, listed[i].assetId, listed[i].ticker, listed[i].name);
            assertTrue(MerkleProof.verify(LibListingTree.proof(listed, i), root, leaf), "proof verifies");
        }
    }

    /// A one-row listing's root is its leaf and its proof is empty.
    function testOneRow() external pure {
        ListingRow[] memory listed = new ListingRow[](1);
        listed[0] = goldenRows()[0];
        assertEq(
            LibListingTree.root(listed),
            LibListing.leaf(listed[0].token, listed[0].assetId, listed[0].ticker, listed[0].name),
            "root"
        );
        assertEq(LibListingTree.proof(listed, 0).length, 0, "proof");
    }

    /// The rows of the token table carry each row's V6 token address.
    function testRowsOfTheTokenTable() external pure {
        TokenConfig[] memory configs = LibProdTokenConfig.testTokenConfigs();
        ListingRow[] memory listed = LibListingTree.rows(configs);
        assertEq(listed.length, configs.length, "length");
        for (uint256 i = 0; i < configs.length; i++) {
            assertEq(listed[i].assetId, configs[i].assetId, "asset id");
            assertEq(listed[i].ticker, configs[i].underlying, "ticker");
            assertEq(listed[i].name, configs[i].underlyingName, "name");
            assertTrue(listed[i].token != address(0), "token");
        }
        LibListingTree.root(listed);
    }

    /// Each row names its own config's V6 token address, in both tables.
    function testRowsCarryEachConfigsOwnTokenAddress() external pure {
        TokenConfig[][2] memory tables = [LibProdTokenConfig.testTokenConfigs(), LibProdTokenConfig.v6TokenConfigs()];
        for (uint256 t = 0; t < tables.length; t++) {
            ListingRow[] memory listed = LibListingTree.rows(tables[t]);
            for (uint256 i = 0; i < listed.length; i++) {
                assertEq(
                    listed[i].token,
                    LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(
                        LibProdTokenParams.tokenParam(tables[t][i])
                    ),
                    "row token"
                );
            }
        }
    }

    function externalRoot(ListingRow[] memory listed) external pure returns (bytes32) {
        return LibListingTree.root(listed);
    }

    function externalRows(TokenConfig[] memory configs) external pure returns (ListingRow[] memory) {
        return LibListingTree.rows(configs);
    }

    function testRefusesNoRows() external {
        vm.expectRevert(ListingWithoutRows.selector);
        this.externalRoot(new ListingRow[](0));
    }

    function testRefusesADuplicateToken() external {
        ListingRow[] memory listed = goldenRows();
        listed[3].token = listed[1].token;
        vm.expectRevert(abi.encodeWithSelector(ListingDuplicateToken.selector, listed[1].token));
        this.externalRoot(listed);
    }

    /// Two rows for one token are refused at any pair of positions.
    function testRefusesADuplicateTokenAtAnyPair(uint8 first, uint8 second) external {
        ListingRow[] memory listed = goldenRows();
        uint256 a = bound(first, 0, listed.length - 2);
        uint256 b = bound(second, a + 1, listed.length - 1);
        listed[b].token = listed[a].token;
        vm.expectRevert(abi.encodeWithSelector(ListingDuplicateToken.selector, listed[a].token));
        this.externalRoot(listed);
    }

    /// Adjacent duplicates at the start and at the end are refused.
    function testRefusesAdjacentDuplicateTokens() external {
        uint256[2][2] memory pairs = [[uint256(0), uint256(1)], [uint256(3), uint256(4)]];
        for (uint256 p = 0; p < pairs.length; p++) {
            ListingRow[] memory listed = goldenRows();
            listed[pairs[p][1]].token = listed[pairs[p][0]].token;
            vm.expectRevert(abi.encodeWithSelector(ListingDuplicateToken.selector, listed[pairs[p][0]].token));
            this.externalRoot(listed);
        }
    }

    function testRefusesARowWithoutAssetId() external {
        TokenConfig[] memory configs = LibProdTokenConfig.testTokenConfigs();
        configs[1].assetId = "";
        vm.expectRevert(abi.encodeWithSelector(ListingRowWithoutAssetId.selector, 1));
        this.externalRows(configs);
    }

    function testRefusesAMalformedRow() external {
        TokenConfig[] memory configs = new TokenConfig[](1);
        configs[0] = TokenConfig({
            underlying: "nvda",
            name: "",
            symbol: "",
            region: Region.US,
            underlyingName: "NVIDIA Corporation",
            assetId: "US67066G1040"
        });
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlying.selector, "nvda", "NVIDIA Corporation"));
        this.externalRows(configs);
        configs[0].underlying = "NVDA";
        configs[0].underlyingName = "";
        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlying.selector, "NVDA", ""));
        this.externalRows(configs);
    }
}
