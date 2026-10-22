// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibStoxMigrations} from "../../../src/lib/LibStoxMigrations.sol";

/// @title LibStoxMigrationsHarness
/// @notice External-call shim so `vm.expectRevert` can see the library's
/// typed revert.
contract LibStoxMigrationsHarness {
    function governanceTimelockExecution(uint256 chainId) external pure returns (uint256, uint256) {
        return LibStoxMigrations.governanceTimelockExecution(chainId);
    }
}
