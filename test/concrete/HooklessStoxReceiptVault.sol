// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVault,
    OffchainAssetReceiptVaultConfigV2
} from "rain-vats-0.2.18/src/abstract/OffchainAssetReceiptVault.sol";
import {StoxReceiptVault} from "../../src/concrete/StoxReceiptVault.sol";

/// A vault implementation as it was before the asset id: no init hook, and a
/// named init. Stands in for the implementation behind a live token.
contract HooklessStoxReceiptVault is StoxReceiptVault {
    function _initialize(OffchainAssetReceiptVaultConfigV2 memory config) internal override {
        OffchainAssetReceiptVault._initialize(config);
    }
}
