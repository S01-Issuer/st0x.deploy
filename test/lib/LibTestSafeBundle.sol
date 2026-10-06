// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibSafeOps, SafeTx} from "../../src/lib/LibSafeOps.sol";

/// @title LibTestSafeBundle
/// @notice Executes an authored bundle the way the Safe UI will: one
/// `execTransaction` that delegatecalls `MultiSendCallOnly` with the
/// encoded batch, signed by `threshold` owners through `approveHash`. Each
/// inner call is therefore made by the Safe itself, so a contract that keys
/// on `msg.sender` (the migration registry) sees the Safe, not a prank.
library LibTestSafeBundle {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Execute `txs` as one MultiSend from `safe` at its live nonce.
    /// @param safe The executing Safe.
    /// @param txs The bundle.
    /// @param threshold The Safe's threshold.
    function execute(IGnosisSafe safe, SafeTx[] memory txs, uint256 threshold) internal {
        bytes memory data = LibSafeOps.encodeMultiSend(txs);
        bytes32 safeTxHash = LibSafeOps.computeMultiSendSafeTxHash(safe, txs, safe.nonce());

        address[] memory owners = safe.getOwners();
        address[] memory approvers = new address[](threshold);
        for (uint256 i = 0; i < threshold; i++) {
            approvers[i] = owners[i];
            VM.prank(owners[i]);
            safe.approveHash(safeTxHash);
        }
        bytes memory signatures =
            LibSafeOps.packApprovedHashSignatures(LibSafeOps.sortAddressesAscending(approvers), threshold);

        bool ok = safe.execTransaction(
            LibSafeOps.MULTISEND_CALL_ONLY_1_4_1, 0, data, 1, 0, 0, 0, address(0), payable(address(0)), signatures
        );
        require(ok, "LibTestSafeBundle: execTransaction failed");
    }
}
