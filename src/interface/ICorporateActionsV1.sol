// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {CorporateActionNode} from "../lib/LibCorporateAction.sol";

/// @title ICorporateActionsV1
/// @notice Versioned interface for corporate actions on a vault. External
/// consumers — oracles, lending protocols, wrapper contracts — import this
/// interface rather than the concrete facet so they can depend on a stable API
/// while the implementation evolves behind it.
interface ICorporateActionsV1 {
    /// @notice Returns the current global corporate action ID — the count of
    /// all completed corporate actions. Computed by walking the linked list
    /// and counting nodes whose effectiveTime has passed.
    function globalCAID() external view returns (uint256);

    /// @notice Schedule a new corporate action. Inserts into the time-ordered
    /// linked list. effectiveTime must be in the future.
    /// @param actionType Bitmap identifying the action type.
    /// @param effectiveTime When the action takes effect.
    /// @param parameters ABI-encoded parameters specific to the action type.
    /// @return nodeId The internal node ID assigned to this action.
    function scheduleCorporateAction(uint256 actionType, uint64 effectiveTime, bytes calldata parameters)
        external
        returns (uint256 nodeId);

    /// @notice Cancel a scheduled action. Only works if effectiveTime hasn't
    /// passed yet. Removes the node from the linked list.
    /// @param nodeId The internal node ID to cancel.
    function cancelCorporateAction(uint256 nodeId) external;
}
