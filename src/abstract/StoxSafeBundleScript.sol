// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.38/src/abstract/SafeBundleScript.sol";
import {LibSafeFork} from "rain-deploy-0.1.38/src/lib/LibSafeFork.sol";
import {LibSafeTx, SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";

/// @notice The queue file's arrays differ in length.
error SafeQueueMalformed();

/// @notice A queued transaction is not at the Safe's next nonce.
/// @param expected The Safe's nonce.
/// @param actual The queued transaction's nonce.
error SafeQueueNonceMismatch(uint256 expected, uint256 actual);

/// @notice A queued transaction's `safeTxHash` is not the hash of its fields at its nonce.
/// @param nonce The nonce.
/// @param expected The `safeTxHash` the queue holds.
/// @param actual The hash of the queued fields.
error SafeQueueHashMismatch(uint256 nonce, bytes32 expected, bytes32 actual);

/// @title StoxSafeBundleScript
/// @notice `SafeBundleScript` that authors its bundle on top of the Safe transactions queued ahead of it.
abstract contract StoxSafeBundleScript is SafeBundleScript {
    /// @return The Safe the bundle is for.
    function queueSafe() external view returns (address) {
        return address(safe());
    }

    /// @notice Executes on the fork, through the Safe, every transaction in the queue file at `SAFE_QUEUE`, if it
    /// exists, in nonce order from the Safe's live nonce, each checked against its `safeTxHash`. The script's
    /// entrypoint then runs on top of the queue.
    function setUp() public virtual {
        string memory path = vm.envOr("SAFE_QUEUE", string(""));
        if (bytes(path).length == 0 || !vm.exists(path)) return;
        string memory json = vm.readFile(path);
        address[] memory to = vm.parseJsonAddressArray(json, ".to");
        uint256[] memory value = vm.parseJsonUintArray(json, ".value");
        bytes[] memory data = vm.parseJsonBytesArray(json, ".data");
        uint256[] memory operation = vm.parseJsonUintArray(json, ".operation");
        uint256[] memory nonce = vm.parseJsonUintArray(json, ".nonce");
        bytes32[] memory safeTxHash = vm.parseJsonBytes32Array(json, ".safeTxHash");
        if (
            value.length != to.length || data.length != to.length || operation.length != to.length
                || nonce.length != to.length || safeTxHash.length != to.length
        ) revert SafeQueueMalformed();

        Safe queued = safe();
        for (uint256 queueIndex = 0; queueIndex < to.length; queueIndex++) {
            if (nonce[queueIndex] != queued.nonce()) revert SafeQueueNonceMismatch(queued.nonce(), nonce[queueIndex]);
            SafeTx memory txn = SafeTx({
                to: to[queueIndex],
                value: value[queueIndex],
                data: data[queueIndex],
                operation: Enum.Operation(uint8(operation[queueIndex]))
            });
            bytes32 actual = LibSafeTx.safeTxHash(queued, txn, nonce[queueIndex]);
            if (actual != safeTxHash[queueIndex]) {
                revert SafeQueueHashMismatch(nonce[queueIndex], safeTxHash[queueIndex], actual);
            }
            LibSafeFork.execute(vm, queued, txn);
        }
    }
}
