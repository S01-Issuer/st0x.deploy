// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.21/src/lib/LibRainDeploy.sol";
import {LibICloneableFactoryV5} from "rain-factory-0.2.4/src/lib/LibICloneableFactoryV5.sol";
import {
    ConfigRegistryOffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.7-pr349/src/concrete/authorize/ConfigRegistryOffchainAssetReceiptVaultAuthorizerV1.sol";

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
        ConfigRegistryOffchainAssetReceiptVaultAuthorizerV1Config memory config =
            abi.decode(LibAuthoriserClone.cloneData(), (ConfigRegistryOffchainAssetReceiptVaultAuthorizerV1Config));
        assertEq(config.authority, LibStoxConfig.ROOT_AUTHORITY);
        assertEq(config.adminName, LibStoxConfig.AUTHORISER_ADMIN);
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
