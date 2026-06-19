// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibRebase} from "src/lib/LibRebase.sol";
import {LibCorporateAction} from "src/lib/LibCorporateAction.sol";

contract LibRebaseHarness {
    function schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters) external returns (uint256) {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function migratedBalance(uint256 storedBalance, uint256 cursor) external view returns (uint256, uint256) {
        return LibRebase.migratedBalance(storedBalance, cursor);
    }
}
