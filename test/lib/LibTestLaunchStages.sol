// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

/// @title LibTestLaunchStages
/// @notice Writes a launch stage file in the shape of forge's broadcast file,
/// from logs recorded in a test, where no broadcast file exists.
library LibTestLaunchStages {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function write(string memory path, Vm.Log[] memory logs, uint256 blockNumber, bool success) internal {
        string memory entries = "";
        for (uint256 i = 0; i < logs.length; i++) {
            string memory topics = "";
            for (uint256 j = 0; j < logs[i].topics.length; j++) {
                topics = string.concat(topics, j == 0 ? "" : ",", "\"", VM.toString(logs[i].topics[j]), "\"");
            }
            entries = string.concat(
                entries,
                i == 0 ? "" : ",",
                "{\"address\":\"",
                VM.toString(logs[i].emitter),
                "\",\"topics\":[",
                topics,
                "],\"data\":\"",
                VM.toString(logs[i].data),
                "\"}"
            );
        }
        VM.writeFile(
            path,
            string.concat(
                "{\"receipts\":[{\"status\":\"",
                success ? "0x1" : "0x0",
                "\",\"blockNumber\":\"",
                VM.toString(bytes32(blockNumber)),
                "\",\"logs\":[",
                entries,
                "]}]}"
            )
        );
    }
}
