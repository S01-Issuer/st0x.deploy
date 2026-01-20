// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {OffchainAssetReceiptVault} from "ethgild/concrete/vault/OffchainAssetReceiptVault.sol";

/// @title StoxReceiptVault
/// @notice An OffchainAssetReceiptVault specialized for StoxReceipts. Currently
/// there are no modifications to the base contract, but this is here to prepare
/// for any future upgrades.
contract StoxReceiptVault is OffchainAssetReceiptVault {}
