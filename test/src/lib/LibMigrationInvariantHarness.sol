// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibMigrationInvariant} from "../../../src/lib/LibMigrationInvariant.sol";

/// @title LibMigrationInvariantHarness
/// @notice External-call shim around the internal library so `vm.expectRevert`
/// can intercept the typed errors. `vm.expectRevert` only catches reverts from
/// external calls; library `internal` functions inline and would fail the
/// depth check otherwise. One `call*` per overload so each `bytes32` /
/// `address` / `uint256` signature is exercised end-to-end.
contract LibMigrationInvariantHarness {
    function callAssertMigrationBytes32(
        string memory label,
        bytes32 actual,
        bytes32 pre,
        bytes32 post,
        uint256 deadline
    ) external view {
        LibMigrationInvariant.assertMigration(label, actual, pre, post, deadline);
    }

    function callAssertMigrationAddress(
        string memory label,
        address actual,
        address pre,
        address post,
        uint256 deadline
    ) external view {
        LibMigrationInvariant.assertMigration(label, actual, pre, post, deadline);
    }

    function callAssertMigrationUint256(
        string memory label,
        uint256 actual,
        uint256 pre,
        uint256 post,
        uint256 deadline
    ) external view {
        LibMigrationInvariant.assertMigration(label, actual, pre, post, deadline);
    }
}
