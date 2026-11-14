// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IStoxUnderlyingV2} from "../../src/interface/IStoxUnderlyingV2.sol";

/// @dev An intermediate contract that forwards `setUnderlying`, so the vault
/// sees this contract as `msg.sender` while `tx.origin` is whoever called it.
contract UnderlyingSetForwarder {
    function forward(IStoxUnderlyingV2 vault, string memory newSymbol, string memory newName, string memory newIsin)
        external
    {
        vault.setUnderlying(newSymbol, newName, newIsin);
    }
}
