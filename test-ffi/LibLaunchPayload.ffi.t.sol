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
            LibTestLaunchChain.PublishedDocuments memory p = LibTestLaunchChain.publishedDocuments(FIXTURE, i);
            LaunchPayloads memory payloads = LibLaunchPayload.withCids(
                p.metadataFile,
                p.tokenName,
                LibTestLaunchChain.cidOf(p.schemaDocument),
                LibTestLaunchChain.cidOf(p.metadataDocument)
            );
            _assertPublished(payloads, p);
        }
    }

    function testUploadsReproduceEveryPublishedDocument() external {
        vm.setEnv(
            "NODE_OPTIONS",
            string.concat("--import=file://", vm.projectRoot(), "/test/fixtures/launch/pinata-fetch.mjs")
        );
        vm.setEnv("PINATA_JWT", "launch-test");
        for (uint256 i = 0; i < 5; i++) {
            LibTestLaunchChain.PublishedDocuments memory p = LibTestLaunchChain.publishedDocuments(FIXTURE, i);
            vm.setEnv("LAUNCH_TEST_SCHEMA_CID", LibTestLaunchChain.cidOf(p.schemaDocument));
            vm.setEnv("LAUNCH_TEST_METADATA_CID", LibTestLaunchChain.cidOf(p.metadataDocument));
            LaunchPayloads memory payloads = LibLaunchPayload.upload(p.metadataFile, p.tokenName);
            _assertPublished(payloads, p);
        }
    }

    function _assertPublished(LaunchPayloads memory payloads, LibTestLaunchChain.PublishedDocuments memory p)
        internal
        pure
    {
        assertEq(payloads.schemaMeta, p.schemaDocument, p.symbol);
        assertEq(payloads.metadataMeta, p.metadataDocument, p.symbol);
        assertEq(payloads.schemaCid, LibTestLaunchChain.cidOf(p.schemaDocument), p.symbol);
        assertEq(payloads.metadataCid, LibTestLaunchChain.cidOf(p.metadataDocument), p.symbol);
    }
}
