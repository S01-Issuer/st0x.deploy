// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.43/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.43/src/lib/LibRegistryAuthority.sol";
import {
    OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CONFIG_V2_TAG,
    OffchainAssetReceiptVaultAuthorizerV1ConfigV2
} from "rain-vats-0.2.25/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibAuthoriserClone} from "../../../src/lib/LibAuthoriserClone.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";

contract LibAuthoriserCloneTest is Test {
    function testCloneDataNamesTheAuthoriserInitialAdminBindingUnderTheRoot() external pure {
        bytes memory data = LibAuthoriserClone.cloneData();
        assertEq(data.length, 0x60, "canonical length");
        (bytes32 tag, OffchainAssetReceiptVaultAuthorizerV1ConfigV2 memory config) =
            abi.decode(data, (bytes32, OffchainAssetReceiptVaultAuthorizerV1ConfigV2));
        assertEq(tag, OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CONFIG_V2_TAG, "tag");
        assertEq(config.authority, LibRegistryAuthority.ROOT_AUTHORITY, "authority");
        assertEq(config.initialAdminName, LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME, "initial admin name");
    }

    function testCloneImplementationIsTheCompiledAuthoriser() external pure {
        assertEq(
            LibAuthoriserClone.implementation(),
            LibRainDeploy.zoltuAddress(type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode)
        );
    }
}
