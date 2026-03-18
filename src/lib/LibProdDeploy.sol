// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibProdDeploy
/// @notice Version-independent production deployment constants.
library LibProdDeploy {
    /// @dev The initial owner for beacon set deployers. Resolves to
    /// rainlang.eth.
    /// https://basescan.org/address/0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b
    address constant BEACON_INITIAL_OWNER = address(0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b);
}
