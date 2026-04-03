// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "rain.math.float/lib/LibDecimalFloat.sol";

/// @title ICorporateActionsV1
/// @notice Versioned interface for corporate actions on a vault. External
/// consumers — oracles, lending protocols, wrapper contracts — import this
/// interface rather than the concrete facet so they can depend on a stable API
/// while the implementation evolves behind it.
interface ICorporateActionsV1 {
    /// @notice Returns the current global corporate action ID. Incremented
    /// each time a corporate action completes. External contracts use this to
    /// detect whether new corporate actions have occurred since they last
    /// checked.
    function globalCAID() external view returns (uint256);

    /// @notice Returns the current rebase count. Only incremented when a
    /// balance-affecting action (e.g. stock split) completes.
    function rebaseCount() external view returns (uint256);

    /// @notice Returns the multiplier at a given rebase ID (1-based).
    /// @param rebaseId The rebase ID to query.
    /// @return multiplier The Rain float multiplier.
    function getMultiplier(uint256 rebaseId) external view returns (Float multiplier);

    /// @notice Returns a completed action by its monotonic ID.
    /// @param monotonicId The monotonic ID to query.
    /// @return actionType The bitmap action type.
    /// @return effectiveTime When the action took effect.
    /// @return parameters The ABI-encoded action parameters.
    function getAction(uint256 monotonicId)
        external
        view
        returns (uint256 actionType, uint64 effectiveTime, bytes memory parameters);

    /// @notice Returns pending (scheduled) action node IDs matching a mask.
    /// @param mask Bitmap mask for filtering.
    /// @param maxResults Maximum number of results.
    /// @return nodeIds Array of matching node IDs (most recent first).
    function getPendingActions(uint256 mask, uint256 maxResults) external view returns (uint256[] memory nodeIds);

    /// @notice Returns the most recent completed action matching a mask.
    /// @param mask Bitmap mask for filtering.
    /// @return nodeId The matching node ID, or 0 if none.
    function getRecentAction(uint256 mask) external view returns (uint256 nodeId);
}
