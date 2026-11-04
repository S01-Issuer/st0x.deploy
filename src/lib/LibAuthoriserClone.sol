// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibICloneableFactoryV5} from "rain-factory-0.2.10/src/lib/LibICloneableFactoryV5.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_ADDRESS
} from "rain-factory-deploy-0.2.6/src/generated/0_2_1/CloneFactory.sol";
import {
    OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CONFIG_V2_TAG,
    OffchainAssetReceiptVaultAuthorizerV1ConfigV2
} from "rain-vats-0.2.19/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {LibStoxConfig} from "./LibStoxConfig.sol";

/// @dev Open, so the address covers the implementation and the init data and
/// not the caller.
bytes32 constant AUTHORISER_CLONE_SALT = keccak256("st0x.authoriser.v4");

/// @title LibAuthoriserClone
/// @notice The V4 authoriser clone's derivations. Its init data names the
/// registry binding the initial admin is resolved from, not the admin, so the
/// address is the same on every chain.
library LibAuthoriserClone {
    /// @notice The init data: `LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME`
    /// under the root authority, tagged V2.
    /// @return The `abi.encode`d tag and config.
    function cloneData() internal pure returns (bytes memory) {
        return abi.encode(
            OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CONFIG_V2_TAG,
            OffchainAssetReceiptVaultAuthorizerV1ConfigV2({
                authority: LibStoxConfig.ROOT_AUTHORITY, initialAdminName: LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME
            })
        );
    }

    /// @notice The clone factory's address for a clone of `implementation`.
    /// @param implementation The implementation.
    /// @return The address.
    function cloneDeployedAddress(address implementation) internal pure returns (address) {
        return LibICloneableFactoryV5.predictCloneAddress(
            CLONE_FACTORY_ADDRESS,
            implementation,
            LibICloneableFactoryV5.effectiveOpenSalt(AUTHORISER_CLONE_SALT, cloneData())
        );
    }
}
