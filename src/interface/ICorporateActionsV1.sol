// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title ICorporateActionsV1
/// @notice Versioned interface for corporate actions on a vault. External
/// consumers — oracles, lending protocols, wrapper contracts — import this
/// interface rather than the concrete facet so they can depend on a stable API
/// while the implementation evolves behind it.
///
/// Functions are added as the implementation grows across PRs.
interface ICorporateActionsV1 {
    /// @notice Schedule a new corporate action.
    /// @param actionType Bitmap identifying the action type.
    /// @param effectiveTime When the action takes effect. Must be in the future.
    /// @param parameters ABI-encoded parameters specific to the action type.
    /// @return nodeId The internal node ID assigned to this action.
    function scheduleCorporateAction(uint256 actionType, uint64 effectiveTime, bytes calldata parameters)
        external
        returns (uint256 nodeId);

    /// @notice Cancel a scheduled action whose effectiveTime hasn't passed.
    /// @param nodeId The internal node ID to cancel.
    function cancelCorporateAction(uint256 nodeId) external;

    /// @notice Count of all completed corporate actions (globalCAID).
    function globalCAID() external view returns (uint256);
}
