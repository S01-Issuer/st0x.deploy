// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {MockERC20} from "./MockERC20.sol";

/// @dev ERC20 asset exposing settable `underlyingSymbol()` / `underlyingName()`
/// getters, standing in for a `StoxReceiptVault`.
contract MockUnderlyingERC20 is MockERC20 {
    string internal sUnderlyingSymbol;
    string internal sUnderlyingName;

    function setUnderlyingValues(string memory newSymbol, string memory newName) external {
        sUnderlyingSymbol = newSymbol;
        sUnderlyingName = newName;
    }

    function underlyingSymbol() external view returns (string memory) {
        return sUnderlyingSymbol;
    }

    function underlyingName() external view returns (string memory) {
        return sUnderlyingName;
    }
}
