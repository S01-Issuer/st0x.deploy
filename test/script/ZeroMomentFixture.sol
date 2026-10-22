// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IStoxHistoryMigration} from "../../src/interface/IStoxScript.sol";

/// @dev A history migration that gives no moment.
contract ZeroMomentFixture is IStoxHistoryMigration {
    function executedAt(uint256) external pure returns (uint256) {
        return 0;
    }
}
