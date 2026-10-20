// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

/// @notice One log of a mined launch transaction.
struct StageLog {
    address emitter;
    bytes32[] topics;
    bytes data;
}

/// @notice One mined launch transaction, from forge's broadcast file.
struct StageReceipt {
    bool success;
    uint256 blockNumber;
    StageLog[] logs;
}

/// @title LibLaunchStages
/// @notice Reads the receipts of a launch stage out of a copy of forge's
/// broadcast file (`broadcast/<script>/8453/<sig>-latest.json`), so the next
/// stage acts on mined addresses rather than on addresses predicted in its own
/// simulation.
library LibLaunchStages {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 internal constant DEPLOYMENT_TOPIC = keccak256("Deployment(address,address,address)");
    bytes32 internal constant NEW_CLONE_TOPIC = keccak256("NewClone(address,address,address)");
    bytes32 internal constant AUTHORIZER_SET_TOPIC = keccak256("AuthorizerSet(address,address)");
    bytes32 internal constant OWNERSHIP_TRANSFERRED_TOPIC = keccak256("OwnershipTransferred(address,address)");

    /// @notice The receipts in a stage file, or none when it does not exist.
    function readReceipts(string memory path) internal view returns (StageReceipt[] memory receipts) {
        if (!VM.exists(path)) return receipts;
        string memory json = VM.readFile(path);
        uint256 count = _length(json, "$.receipts");
        receipts = new StageReceipt[](count);
        for (uint256 i = 0; i < count; i++) {
            string memory key = string.concat("$.receipts[", VM.toString(i), "]");
            receipts[i].success = VM.parseUint(VM.parseJsonString(json, string.concat(key, ".status"))) == 1;
            receipts[i].blockNumber = VM.parseUint(VM.parseJsonString(json, string.concat(key, ".blockNumber")));
            uint256 logCount = _length(json, string.concat(key, ".logs"));
            receipts[i].logs = new StageLog[](logCount);
            for (uint256 j = 0; j < logCount; j++) {
                string memory logKey = string.concat(key, ".logs[", VM.toString(j), "]");
                receipts[i].logs[j].emitter = VM.parseJsonAddress(json, string.concat(logKey, ".address"));
                receipts[i].logs[j].topics = VM.parseJsonBytes32Array(json, string.concat(logKey, ".topics"));
                receipts[i].logs[j].data = VM.parseJsonBytes(json, string.concat(logKey, ".data"));
            }
        }
    }

    /// @notice The hashes forge sent but holds no receipt for.
    function pendingHashes(string memory path) internal view returns (string[] memory) {
        if (!VM.exists(path)) return new string[](0);
        string memory json = VM.readFile(path);
        if (!VM.keyExistsJson(json, "$.pending")) return new string[](0);
        return VM.parseJsonStringArray(json, "$.pending");
    }

    /// @notice Logs recorded with `vm.recordLogs`, as one successful receipt.
    function fromRecordedLogs(Vm.Log[] memory recorded, uint256 blockNumber)
        internal
        pure
        returns (StageReceipt memory receipt)
    {
        receipt.success = true;
        receipt.blockNumber = blockNumber;
        receipt.logs = new StageLog[](recorded.length);
        for (uint256 i = 0; i < recorded.length; i++) {
            receipt.logs[i] =
                StageLog({emitter: recorded[i].emitter, topics: recorded[i].topics, data: recorded[i].data});
        }
    }

    /// @notice The pair from the unified deployer's `Deployment` event in a
    /// successful receipt.
    function findDeployment(StageReceipt[] memory receipts, address unifiedDeployer)
        internal
        pure
        returns (bool found, address vault, address wrapper, uint256 blockNumber)
    {
        for (uint256 i = 0; i < receipts.length; i++) {
            if (!receipts[i].success) continue;
            for (uint256 j = 0; j < receipts[i].logs.length; j++) {
                StageLog memory log = receipts[i].logs[j];
                if (log.emitter != unifiedDeployer || log.topics.length == 0 || log.topics[0] != DEPLOYMENT_TOPIC) {
                    continue;
                }
                (, vault, wrapper) = abi.decode(log.data, (address, address, address));
                found = true;
                return (found, vault, wrapper, receipts[i].blockNumber);
            }
        }
    }

    /// @notice The clone from the factory's `NewClone` event in a successful
    /// receipt.
    function findClone(StageReceipt[] memory receipts, address factory)
        internal
        pure
        returns (bool found, address clone, uint256 blockNumber)
    {
        for (uint256 i = 0; i < receipts.length; i++) {
            if (!receipts[i].success) continue;
            for (uint256 j = 0; j < receipts[i].logs.length; j++) {
                StageLog memory log = receipts[i].logs[j];
                if (log.emitter != factory || log.topics.length == 0 || log.topics[0] != NEW_CLONE_TOPIC) continue;
                (,, clone) = abi.decode(log.data, (address, address, address));
                found = true;
                return (found, clone, receipts[i].blockNumber);
            }
        }
    }

    /// @notice Whether a successful receipt holds `vault`'s `AuthorizerSet` to
    /// `authoriser`.
    function setAuthorizerLanded(StageReceipt[] memory receipts, address vault, address authoriser)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < receipts.length; i++) {
            if (!receipts[i].success) continue;
            for (uint256 j = 0; j < receipts[i].logs.length; j++) {
                StageLog memory log = receipts[i].logs[j];
                if (log.emitter != vault || log.topics.length == 0 || log.topics[0] != AUTHORIZER_SET_TOPIC) continue;
                (, address newAuthoriser) = abi.decode(log.data, (address, address));
                if (newAuthoriser == authoriser) return true;
            }
        }
        return false;
    }

    /// @notice Whether a successful receipt holds `vault`'s ownership transfer
    /// to `newOwner`.
    function ownershipTransferred(StageReceipt[] memory receipts, address vault, address newOwner)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < receipts.length; i++) {
            if (!receipts[i].success) continue;
            for (uint256 j = 0; j < receipts[i].logs.length; j++) {
                StageLog memory log = receipts[i].logs[j];
                if (
                    log.emitter == vault && log.topics.length == 3 && log.topics[0] == OWNERSHIP_TRANSFERRED_TOPIC
                        && log.topics[2] == bytes32(uint256(uint160(newOwner)))
                ) return true;
            }
        }
        return false;
    }

    function _length(string memory json, string memory key) private view returns (uint256 count) {
        while (VM.keyExistsJson(json, string.concat(key, "[", VM.toString(count), "]"))) {
            count++;
        }
    }
}
