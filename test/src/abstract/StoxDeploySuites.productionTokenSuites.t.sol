// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {
    LibRainDeployCloneMechanism,
    REGISTRY_BEACON_PROXY_MECHANISM
} from "rain-factory-0.2.10/src/lib/LibRainDeployCloneMechanism.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibStoxTestTokens} from "../../../src/lib/LibStoxTestTokens.sol";

/// @title StoxDeploySuitesProductionTokenSuitesTest
/// @notice The production declaration has a token suite for each V6 row and each test token only: a production row
/// with an empty asset id has none.
contract StoxDeploySuitesProductionTokenSuitesTest is Test, StoxDeploySuites {
    function testOnlyV6RowsAreDeclaredTokenSuites() external view {
        DeployDeclaration memory declared = declaration();
        TokenConfig[] memory v6 = LibProdTokenConfig.v6TokenConfigs();
        uint256 count = 0;
        for (uint256 i = 0; i < declared.candidates.length; i++) {
            if (
                mechanismIdOf(declared.candidates[i].snapshot) == REGISTRY_BEACON_PROXY_MECHANISM
                    && LibRainDeployCloneMechanism.registryBeaconProxyTarget(declared.candidates[i].snapshot).beaconName
                        == LibStoxConfig.VAULT_BEACON_NAME
            ) {
                count++;
            }
        }
        assertEq(count, v6.length + LibStoxTestTokens.testTokenConfigs().length, "one suite per V6 and test row");
        TokenConfig[] memory production = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 i = 0; i < production.length; i++) {
            if (bytes(production[i].assetId).length == 0) {
                (, bool found) = candidateOf(declared, string.concat(TOKEN_PREFIX, lowercase(production[i].symbol)));
                assertFalse(found, production[i].underlying);
            }
        }
    }
}
