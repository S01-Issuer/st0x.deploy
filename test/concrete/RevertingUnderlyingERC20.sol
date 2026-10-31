// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {MockERC20} from "./MockERC20.sol";

/// @dev ERC20 asset whose underlying getters revert with data.
contract RevertingUnderlyingERC20 is MockERC20 {
    error NoUnderlying();

    function underlyingSymbol() external pure returns (string memory) {
        revert NoUnderlying();
    }

    function underlyingName() external pure returns (string memory) {
        revert NoUnderlying();
    }
}
