// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibLaunchPayload, LaunchPayloads} from "../script/lib/LibLaunchPayload.sol";
import {LibTestLaunchChain} from "../test/lib/LibTestLaunchChain.sol";

contract LibLaunchPayloadFfiTest is Test {
    string constant FIXTURE = "test/fixtures/launch/published-documents.json";

    function setUp() external {
        vm.setEnv("NODE_OPTIONS", "");
        vm.setEnv("PINATA_JWT", "");
    }

    function testFixedCidsReproduceEveryPublishedDocument() external {
        for (uint256 i = 0; i < 5; i++) {
            LibTestLaunchChain.PublishedDocuments memory published = LibTestLaunchChain.publishedDocuments(FIXTURE, i);
            LaunchPayloads memory payloads = LibLaunchPayload.withCids(
                published.metadataFile,
                published.tokenName,
                LibTestLaunchChain.cidOf(published.schemaDocument),
                LibTestLaunchChain.cidOf(published.metadataDocument)
            );
            _assertPublished(payloads, published);
        }
    }

    function testUploadsReproduceEveryPublishedDocument() external {
        vm.setEnv(
            "NODE_OPTIONS",
            string.concat("--import=file://", vm.projectRoot(), "/test/fixtures/launch/pinata-fetch.mjs")
        );
        vm.setEnv("PINATA_JWT", "launch-test");
        for (uint256 i = 0; i < 5; i++) {
            LibTestLaunchChain.PublishedDocuments memory published = LibTestLaunchChain.publishedDocuments(FIXTURE, i);
            vm.setEnv("LAUNCH_TEST_SCHEMA_CID", LibTestLaunchChain.cidOf(published.schemaDocument));
            vm.setEnv("LAUNCH_TEST_METADATA_CID", LibTestLaunchChain.cidOf(published.metadataDocument));
            LaunchPayloads memory payloads = LibLaunchPayload.upload(published.metadataFile, published.tokenName);
            _assertPublished(payloads, published);
        }
    }

    /// @notice An upload whose returned CID is empty, or is not the CID of
    /// the uploaded bytes, fails instead of framing a wrong document.
    function testUploadRefusesACidThatIsNotTheUploadedBytes() external {
        vm.setEnv(
            "NODE_OPTIONS",
            string.concat("--import=file://", vm.projectRoot(), "/test/fixtures/launch/pinata-fetch.mjs")
        );
        vm.setEnv("PINATA_JWT", "launch-test");
        LibTestLaunchChain.PublishedDocuments memory published = LibTestLaunchChain.publishedDocuments(FIXTURE, 0);
        string memory metadataCid = LibTestLaunchChain.cidOf(published.metadataDocument);
        vm.setEnv("LAUNCH_TEST_METADATA_CID", metadataCid);

        vm.setEnv("LAUNCH_TEST_SCHEMA_CID", "");
        vm.expectRevert();
        this.upload(published.metadataFile, published.tokenName);

        vm.setEnv("LAUNCH_TEST_SCHEMA_CID", metadataCid);
        vm.expectRevert();
        this.upload(published.metadataFile, published.tokenName);
    }

    function upload(string memory metadataFile, string memory tokenName) external returns (LaunchPayloads memory) {
        return LibLaunchPayload.upload(metadataFile, tokenName);
    }

    function _assertPublished(LaunchPayloads memory payloads, LibTestLaunchChain.PublishedDocuments memory published)
        internal
        pure
    {
        assertEq(payloads.schemaMeta, published.schemaDocument, published.symbol);
        assertEq(payloads.metadataMeta, published.metadataDocument, published.symbol);
        assertEq(payloads.schemaCid, LibTestLaunchChain.cidOf(published.schemaDocument), published.symbol);
        assertEq(payloads.metadataCid, LibTestLaunchChain.cidOf(published.metadataDocument), published.symbol);
    }
}
