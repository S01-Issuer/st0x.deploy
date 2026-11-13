// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {OffchainAssetReceiptVault} from "rain-vats-0.2.20/src/abstract/OffchainAssetReceiptVault.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";

/// Initializes from `OffchainAssetReceiptVaultConfigV3` as vaults did before
/// `StoxTokenConfigV1`, leaving the token config storage empty.
contract LegacyInitStoxReceiptVault is StoxReceiptVault {
    function initializeLegacy(bytes memory data) external returns (bytes32) {
        return OffchainAssetReceiptVault.initialize(data);
    }
}
