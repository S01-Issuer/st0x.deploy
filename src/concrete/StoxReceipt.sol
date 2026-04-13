// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Receipt} from "rain.vats/concrete/receipt/Receipt.sol";

/// @title StoxReceipt
/// @notice A Receipt specialized for Stox. Currently there are no modifications
/// to the base contract, but this is here to prepare for any future upgrades.
/// @dev Inherits `ethgild/concrete/receipt/Receipt.sol`. Implements ICloneableV2:
/// `initialize(bytes)` expects `abi.encode(address manager)`.
contract StoxReceipt is Receipt {}
