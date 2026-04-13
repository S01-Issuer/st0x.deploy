// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {OffchainAssetReceiptVault} from "rain.vats/concrete/vault/OffchainAssetReceiptVault.sol";

/// @title StoxReceiptVault
/// @notice An OffchainAssetReceiptVault specialized for StoxReceipts. Currently
/// there are no modifications to the base contract, but this is here to prepare
/// for any future upgrades.
/// @dev Inherits `ethgild/concrete/vault/OffchainAssetReceiptVault.sol`.
/// Implements ICloneableV2: `initialize(bytes)` expects
/// `abi.encode(OffchainAssetReceiptVaultConfigV2)`. Deployed as a proxy
/// implementation via Zoltu deterministic deployment; constructor disables
/// initializers.
contract StoxReceiptVault is OffchainAssetReceiptVault {}
