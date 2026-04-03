// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

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
}
