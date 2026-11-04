// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibICloneableFactoryV5} from "rain-factory-0.2.4/src/lib/LibICloneableFactoryV5.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_ADDRESS
} from "rain-factory-deploy-0.2.1/src/generated/0_2_1/CloneFactory.sol";
import {
    ConfigRegistryOffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.7-pr349/src/concrete/authorize/ConfigRegistryOffchainAssetReceiptVaultAuthorizerV1.sol";

import {LibStoxConfig} from "./LibStoxConfig.sol";

/// @dev The open salt for the V4 authoriser clone. Open, so the address covers
/// the implementation and the init data and not the caller.
bytes32 constant AUTHORISER_CLONE_SALT = keccak256("st0x.authoriser.v4");

/// @title LibAuthoriserClone
/// @notice The V4 authoriser clone's derivations. Its init data names the
/// `ConfigRegistry` binding the admin is resolved from, not the admin, so the
/// address is the same on every chain.
library LibAuthoriserClone {
    /// @notice The init data: `LibStoxConfig.AUTHORISER_ADMIN` under the root
    /// authority.
    /// @return The `abi.encode`d config.
    function cloneData() internal pure returns (bytes memory) {
        return abi.encode(
            ConfigRegistryOffchainAssetReceiptVaultAuthorizerV1Config({
                authority: LibStoxConfig.ROOT_AUTHORITY, adminName: LibStoxConfig.AUTHORISER_ADMIN
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
