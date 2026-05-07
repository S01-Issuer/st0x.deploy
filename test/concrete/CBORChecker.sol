// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibExtrospectBytecode} from "rain.extrospection/lib/LibExtrospectBytecode.sol";

/// @dev External wrapper for `LibExtrospectBytecode.checkNoSolidityCBORMetadata`.
/// The library function is `internal` so it inlines into the caller; tests
/// that want to assert a revert via `vm.expectRevert` need an external call
/// hop so the revert lands at a depth lower than the cheatcode.
contract CBORChecker {
    function check(address account) external view {
        LibExtrospectBytecode.checkNoSolidityCBORMetadata(account);
    }
}
