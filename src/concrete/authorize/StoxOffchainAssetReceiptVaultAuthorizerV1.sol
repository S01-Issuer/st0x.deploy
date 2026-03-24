// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultAuthorizerV1
} from "ethgild/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

/// @title StoxOffchainAssetReceiptVaultAuthorizerV1
/// @notice An OffchainAssetReceiptVaultAuthorizerV1 specialized for Stox.
/// Currently there are no modifications to the base contract, but this is here
/// to prepare for any future upgrades.
/// @dev Inherits
/// `ethgild/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol`.
/// Implements ICloneableV2: `initialize(bytes)` expects
/// `abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config)`. Deployed as a
/// proxy implementation via Zoltu deterministic deployment; constructor
/// disables initializers.
contract StoxOffchainAssetReceiptVaultAuthorizerV1 is OffchainAssetReceiptVaultAuthorizerV1 {}
