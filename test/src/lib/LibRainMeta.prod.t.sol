// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {LibRainMeta} from "../../../src/lib/LibRainMeta.sol";
import {LibTestLaunchChain} from "../../lib/LibTestLaunchChain.sol";

/// @title LibRainMetaProdTest
/// @notice `test/fixtures/launch/published-documents.json` holds the documents
/// sft-ops published for five live Base tokens: the schema through
/// `ReceiptVaultInformation` and the metadata through `MetaV1_2` for both the
/// vault and the wrapper. These tests prove the fixture is what is on chain,
/// and that `LibRainMeta` frames each document's payload and CID into exactly
/// those bytes. The launch helper's node tests prove it produces the same
/// payloads from `launch/metadata/`.
contract LibRainMetaProdTest is Test {
    string constant FIXTURE = "test/fixtures/launch/published-documents.json";

    function setUp() external {
        vm.createSelectFork(LibRainDeploy.BASE);
    }

    function _document(uint256 i) internal view returns (LibTestLaunchChain.PublishedDocuments memory) {
        return LibTestLaunchChain.publishedDocuments(FIXTURE, i);
    }

    function testDisDocumentsAreOnChainAndFramedByLibRainMeta() external view {
        _assertPublished(_document(0));
    }

    function testWmtDocumentsAreOnChainAndFramedByLibRainMeta() external view {
        _assertPublished(_document(1));
    }

    /// @notice An ETF.
    function testSpyDocumentsAreOnChainAndFramedByLibRainMeta() external view {
        _assertPublished(_document(2));
    }

    /// @notice A non-ASCII token name.
    function testMcDocumentsAreOnChainAndFramedByLibRainMeta() external view {
        _assertPublished(_document(3));
    }

    function testSnesDocumentsAreOnChainAndFramedByLibRainMeta() external view {
        _assertPublished(_document(4));
    }

    function _assertPublished(LibTestLaunchChain.PublishedDocuments memory published) internal view {
        assertEq(
            LibTestLaunchChain.schemaDocument(published.vault, published.schemaBlock),
            published.schemaDocument,
            "schema on chain"
        );
        assertEq(
            LibTestLaunchChain.metaDocument(published.vault, published.vaultMetaBlock),
            published.metadataDocument,
            "vault metadata"
        );
        assertEq(
            LibTestLaunchChain.metaDocument(published.wrapper, published.wrapperMetaBlock),
            published.metadataDocument,
            "wrapper metadata"
        );

        assertEq(
            LibRainMeta.encode(
                LibTestLaunchChain.payloadOf(published.schemaDocument),
                LibTestLaunchChain.cidOf(published.schemaDocument)
            ),
            published.schemaDocument,
            "schema framing"
        );
        assertEq(
            LibRainMeta.encode(
                LibTestLaunchChain.payloadOf(published.metadataDocument),
                LibTestLaunchChain.cidOf(published.metadataDocument)
            ),
            published.metadataDocument,
            "metadata framing"
        );
    }
}
