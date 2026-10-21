// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IReceiptVaultV1} from "rain-vats-0.2.5/src/interface/deprecated/IReceiptVaultV1.sol";
import {LibProdLaunchBase} from "../../src/lib/LibProdLaunchBase.sol";

/// @title LibTestLaunchChain
/// @notice Reads the documents sft-ops published for a live Base token, and
/// the CID inside a Rain meta document, for the launch's prod tests.
library LibTestLaunchChain {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice One token's entry in `test/fixtures/launch/published-documents.json`.
    struct PublishedDocuments {
        string symbol;
        string metadataFile;
        string tokenName;
        address vault;
        address wrapper;
        uint256 schemaBlock;
        uint256 vaultMetaBlock;
        uint256 wrapperMetaBlock;
        bytes schemaDocument;
        bytes metadataDocument;
    }

    function publishedDocuments(string memory fixture, uint256 i) internal view returns (PublishedDocuments memory p) {
        string memory json = VM.readFile(fixture);
        string memory key = string.concat("$[", VM.toString(i), "]");
        p.symbol = VM.parseJsonString(json, string.concat(key, ".symbol"));
        p.metadataFile = VM.parseJsonString(json, string.concat(key, ".metadataFile"));
        p.tokenName = VM.parseJsonString(json, string.concat(key, ".tokenName"));
        p.vault = VM.parseJsonAddress(json, string.concat(key, ".vault"));
        p.wrapper = VM.parseJsonAddress(json, string.concat(key, ".wrapper"));
        p.schemaBlock = VM.parseJsonUint(json, string.concat(key, ".schemaBlock"));
        p.vaultMetaBlock = VM.parseJsonUint(json, string.concat(key, ".vaultMetaBlock"));
        p.wrapperMetaBlock = VM.parseJsonUint(json, string.concat(key, ".wrapperMetaBlock"));
        p.schemaDocument = VM.parseJsonBytes(json, string.concat(key, ".schemaDocument"));
        p.metadataDocument = VM.parseJsonBytes(json, string.concat(key, ".metadataDocument"));
    }

    bytes32 internal constant META_V1_2 = keccak256("MetaV1_2(address,bytes32,bytes)");

    /// @notice The schema document `vault` published in `blockNumber`.
    function schemaDocument(address vault, uint256 blockNumber) internal view returns (bytes memory document) {
        bytes32[] memory topics = new bytes32[](1);
        topics[0] = IReceiptVaultV1.ReceiptVaultInformation.selector;
        Vm.EthGetLogs[] memory logs = VM.eth_getLogs(blockNumber, blockNumber, vault, topics);
        require(logs.length == 1, "expected one schema publication");
        (, document) = abi.decode(logs[0].data, (address, bytes));
    }

    /// @notice The metadata document published for `subject` in `blockNumber`.
    function metaDocument(address subject, uint256 blockNumber) internal view returns (bytes memory) {
        bytes32[] memory topics = new bytes32[](1);
        topics[0] = META_V1_2;
        Vm.EthGetLogs[] memory logs = VM.eth_getLogs(blockNumber, blockNumber, LibProdLaunchBase.METABOARD, topics);
        for (uint256 i = 0; i < logs.length; i++) {
            (, bytes32 loggedSubject, bytes memory meta) = abi.decode(logs[i].data, (address, bytes32, bytes));
            if (loggedSubject == bytes32(uint256(uint160(subject)))) return meta;
        }
        revert("no MetaV1_2 for the subject in the block");
    }

    /// @notice The deflated JSON a document's schema item carries.
    function payloadOf(bytes memory document) internal pure returns (bytes memory payload) {
        (uint256 length, uint256 at) = readHead(document, 10);
        payload = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            payload[i] = document[at + i];
        }
    }

    /// @notice The CID in a document's hash-list item: the text string after
    /// the `a2 00` map and key heads that follow the schema item.
    function cidOf(bytes memory document) internal pure returns (string memory) {
        uint256 at = 10;
        uint256 payloadLength;
        (payloadLength, at) = readHead(document, at);
        at += payloadLength;
        // 1, OA_SCHEMA magic, 2, "application/json", 3, "deflate".
        at += 1 + 9 + 1 + 17 + 1 + 8;
        require(document[at] == 0xa2 && document[at + 1] == 0x00, "no hash list");
        uint256 cidLength;
        (cidLength, at) = readHead(document, at + 2);
        bytes memory cid = new bytes(cidLength);
        for (uint256 i = 0; i < cidLength; i++) {
            cid[i] = document[at + i];
        }
        return string(cid);
    }

    function readHead(bytes memory b, uint256 at) internal pure returns (uint256 value, uint256 next) {
        uint8 info = uint8(b[at]) & 0x1f;
        if (info < 24) return (info, at + 1);
        uint256 size = 2 ** (info - 24);
        for (uint256 i = 0; i < size; i++) {
            value = (value << 8) | uint8(b[at + 1 + i]);
        }
        return (value, at + 1 + size);
    }
}
