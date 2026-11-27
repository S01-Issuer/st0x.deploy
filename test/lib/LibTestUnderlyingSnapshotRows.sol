// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {UnderlyingSnapshotRow} from "../../script/LibUnderlyingSnapshotBuilder.sol";

library LibTestUnderlyingSnapshotRows {
    /// `n` rows of distinct pseudorandom tokens and short fields derived from `seed`.
    function rowsFrom(Vm vm, bytes32 seed, uint256 n) internal pure returns (UnderlyingSnapshotRow[] memory) {
        UnderlyingSnapshotRow[] memory rows = new UnderlyingSnapshotRow[](n);
        for (uint256 i = 0; i < n; i++) {
            bytes32 h = keccak256(abi.encode(seed, i));
            rows[i] = UnderlyingSnapshotRow(
                address(uint160(uint256(h))),
                vm.toString(uint256(uint16(uint256(h)))),
                string.concat("Name ", vm.toString(h)),
                vm.toString(uint256(uint40(uint256(h))))
            );
        }
        return rows;
    }
}
