// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibCorporateAction} from "../../src/lib/LibCorporateAction.sol";

/// @title LibTestCorporateAction
/// @notice Test-only helpers for reading the 1-based head/tail indices of
/// the corporate action linked list. Production code walks the list via
/// `LibCorporateActionNode.nextOfType` / `prevOfType` starting from 0, so it
/// never needs raw index access. Tests inspect these directly to verify
/// link ordering after insertion and cancellation.
library LibTestCorporateAction {
    /// @notice The 1-based index of the head node, or 0 if the list is empty.
    function head() internal view returns (uint256) {
        return LibCorporateAction.getStorage().head;
    }

    /// @notice The 1-based index of the tail node, or 0 if the list is empty.
    function tail() internal view returns (uint256) {
        return LibCorporateAction.getStorage().tail;
    }
}
