// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/ERC20.sol";

/// @dev Minimal ERC20 for testing name/symbol delegation.
contract MockERC20 is ERC20 {
    constructor() ERC20("Test Token", "TT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
