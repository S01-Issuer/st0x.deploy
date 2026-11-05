// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
    OffchainAssetReceiptVaultConfigV3
} from "rain-vats-0.2.18/src/interface/IOffchainAssetReceiptVaultV1.sol";
import {StoxCorporateActionsFacet} from "../../src/concrete/StoxCorporateActionsFacet.sol";
import {StoxReceipt} from "../../src/concrete/StoxReceipt.sol";
import {LibAssetId} from "../../src/lib/LibAssetId.sol";

/// A receipt that, while its vault initializes, calls the vault's
/// `initializeAssetId` with another asset id.
contract ReentrantAssetIdReceipt is StoxReceipt {
    function initialize(bytes memory data) public override returns (bytes32) {
        bytes32 result = super.initialize(data);
        address vault = abi.decode(data, (address));
        StoxCorporateActionsFacet(vault)
            .initializeAssetId(
                abi.encode(
                    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
                    OffchainAssetReceiptVaultConfigV3({
                    name: "",
                    symbol: "",
                    authority: address(0),
                    rbacName: bytes32(0),
                    receiptBeaconName: bytes32(0),
                    metadata: LibAssetId.encodeMetadata("EVIL")
                })
                )
            );
        return result;
    }
}
