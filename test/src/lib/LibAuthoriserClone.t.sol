// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibICloneableFactoryV5} from "rain-factory-0.2.10/src/lib/LibICloneableFactoryV5.sol";
import {
    OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CONFIG_V2_TAG,
    OffchainAssetReceiptVaultAuthorizerV1ConfigV2
} from "rain-vats-0.2.19/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    DEPLOYED_ADDRESS as AUTHORISER
} from "../../../src/generated/candidate/StoxOffchainAssetReceiptVaultAuthorizerV1.pointers.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserClone} from "../../../src/lib/LibAuthoriserClone.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";

/// @title LibAuthoriserCloneTest
/// @notice The registry clone's pins re-derived offline from the compiled
/// implementation.
contract LibAuthoriserCloneTest is Test {
    function testInitDataNamesTheAdminBinding() external pure {
        (bytes32 tag, OffchainAssetReceiptVaultAuthorizerV1ConfigV2 memory config) =
            abi.decode(LibAuthoriserClone.cloneData(), (bytes32, OffchainAssetReceiptVaultAuthorizerV1ConfigV2));
        assertEq(tag, OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CONFIG_V2_TAG);
        assertEq(config.authority, LibStoxConfig.ROOT_AUTHORITY);
        assertEq(config.initialAdminName, LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME);
    }

    function testPinsRederive() external pure {
        address implementation =
            LibRainDeploy.zoltuAddress(type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode);
        assertEq(implementation, AUTHORISER);
        assertEq(
            LibAuthoriserClone.cloneDeployedAddress(implementation), LibProdDeployV4.STOX_AUTHORISER_V4_REGISTRY_CLONE
        );
        bytes memory runtimeCode = LibICloneableFactoryV5.cloneRuntimeCode(implementation);
        assertEq(runtimeCode, LibProdDeployV4.STOX_AUTHORISER_V4_REGISTRY_CLONE_CODE);
        assertEq(keccak256(runtimeCode), LibProdDeployV4.STOX_AUTHORISER_V4_REGISTRY_CLONE_CODEHASH);
    }
}
