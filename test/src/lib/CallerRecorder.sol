// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @notice Stub contract used by `testSimulateExternalCallPrankRoutes` to
/// capture the caller address of an external call. Kept inline because it
/// is single-use and trivially small.
contract CallerRecorder {
    /// @notice The most recent `msg.sender` to call `ping`.
    address public lastCaller;

    /// @notice Records the caller address. No return value; the recording
    /// is the side effect under test.
    function ping() external {
        lastCaller = msg.sender;
    }
}
