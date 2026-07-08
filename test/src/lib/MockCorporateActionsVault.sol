// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {MockCorporateActionsReadBase} from "./MockCorporateActionsReadBase.sol";

/// @dev Mock vault exposing only the subset of `ICorporateActionsV1` that
/// `LibReceiptRebase` consumes (`nextOfType` + `getActionParameters`), inherited
/// from `MockCorporateActionsReadBase`. Tests preload the mock with a list of
/// completed stock split multipliers, and the receipt rebase walks it exactly
/// as if it were a real vault. Adds a raw-blob injection helper and a split
/// count accessor on top of the shared read subset.
contract MockCorporateActionsVault is MockCorporateActionsReadBase {
    function addSplitRaw(bytes memory parameters) external {
        splits.push(parameters);
    }

    function splitCount() external view returns (uint256) {
        return splits.length;
    }
}
