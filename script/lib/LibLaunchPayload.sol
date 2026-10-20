// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainMeta} from "../../src/lib/LibRainMeta.sol";

/// @notice The Rain meta documents one token publishes: the schema through
/// `receiptVaultInformation`, the metadata on the MetaBoard for both the vault
/// and the wrapper.
struct LaunchPayloads {
    bytes schemaMeta;
    string schemaCid;
    bytes metadataMeta;
    string metadataCid;
}

/// @title LibLaunchPayload
/// @notice Calls `launch/ffi/payload.mjs` through `vm.ffi` for the deflated
/// schema and metadata JSON and their IPFS CIDs, and frames each as a Rain meta
/// document. Needs `FOUNDRY_FFI=true` and Node with `launch/ffi` installed.
library LibLaunchPayload {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant HELPER = "launch/ffi/payload.mjs";

    /// @notice Upload the schema and the metadata to Pinata, as sft-ops
    /// `create-sft` does, and return the documents carrying their CIDs.
    function upload(string memory metadataFile, string memory tokenName) internal returns (LaunchPayloads memory) {
        string[] memory cmd = new string[](5);
        cmd[0] = "node";
        cmd[1] = HELPER;
        cmd[2] = metadataFile;
        cmd[3] = tokenName;
        cmd[4] = "--upload";
        return _frame(VM.ffi(cmd));
    }

    /// @notice The documents for given CIDs, with no upload.
    function withCids(
        string memory metadataFile,
        string memory tokenName,
        string memory schemaCid,
        string memory metadataCid
    ) internal returns (LaunchPayloads memory) {
        string[] memory cmd = new string[](8);
        cmd[0] = "node";
        cmd[1] = HELPER;
        cmd[2] = metadataFile;
        cmd[3] = tokenName;
        cmd[4] = "--cid-schema";
        cmd[5] = schemaCid;
        cmd[6] = "--cid-meta";
        cmd[7] = metadataCid;
        return _frame(VM.ffi(cmd));
    }

    function _frame(bytes memory out) private pure returns (LaunchPayloads memory payloads) {
        (bytes memory schemaPayload, string memory schemaCid, bytes memory metadataPayload, string memory metadataCid) =
            abi.decode(out, (bytes, string, bytes, string));
        payloads.schemaMeta = LibRainMeta.encode(schemaPayload, schemaCid);
        payloads.schemaCid = schemaCid;
        payloads.metadataMeta = LibRainMeta.encode(metadataPayload, metadataCid);
        payloads.metadataCid = metadataCid;
    }
}
