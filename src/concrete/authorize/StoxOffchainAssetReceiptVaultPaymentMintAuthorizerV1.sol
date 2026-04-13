// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultPaymentMintAuthorizerV1
} from "rain.vats/concrete/authorize/OffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";

/// @title StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1
/// @notice An OffchainAssetReceiptVaultPaymentMintAuthorizerV1 specialized for
/// Stox. Currently there are no modifications to the base contract, but this is
/// here to prepare for any future upgrades.
/// @dev Inherits
/// `ethgild/concrete/authorize/OffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol`.
/// Implements ICloneableV2: `initialize(bytes)` expects
/// `abi.encode(OffchainAssetReceiptVaultPaymentMintAuthorizerV1Config)`.
/// Deployed as a proxy implementation via Zoltu deterministic deployment;
/// constructor disables initializers.
contract StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 is OffchainAssetReceiptVaultPaymentMintAuthorizerV1 {}
