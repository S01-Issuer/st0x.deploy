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
    /// @param typeHash External identifier for the action type, e.g.
    /// keccak256("StockSplit"). Resolved to an internal bitmap by the lib.
    /// @param effectiveTime When the action takes effect. Must be in the future.
    /// @param parameters ABI-encoded parameters specific to the action type.
    /// @return actionIndex Handle for the scheduled action.
    function scheduleCorporateAction(bytes32 typeHash, uint64 effectiveTime, bytes calldata parameters)
        external
        returns (uint256 actionIndex);

    /// @notice Cancel a scheduled action whose effectiveTime hasn't passed.
    /// @param actionIndex The scheduled action handle to cancel.
    function cancelCorporateAction(uint256 actionIndex) external;

    /// @notice Count of all completed corporate actions. An action is complete
    /// when its effectiveTime has passed. The Nth completed action has
    /// completedActionId = N.
    function completedActionCount() external view returns (uint256);
}
