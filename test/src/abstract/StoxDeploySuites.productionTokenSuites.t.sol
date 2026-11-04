// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {REGISTRY_BEACON_PROXY_MECHANISM} from "rain-factory-0.2.10/src/lib/LibRainDeployCloneMechanism.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";

/// @title StoxDeploySuitesProductionTokenSuitesTest
/// @notice The production declaration has a token suite for each V6 row only: a row with an empty asset id has none.
contract StoxDeploySuitesProductionTokenSuitesTest is Test, StoxDeploySuites {
    function testOnlyV6RowsAreDeclaredTokenSuites() external view {
        DeployDeclaration memory declared = declaration();
        TokenConfig[] memory v6 = LibProdTokenConfig.v6TokenConfigs();
        uint256 count = 0;
        for (uint256 i = 0; i < declared.candidates.length; i++) {
            if (mechanismIdOf(declared.candidates[i].snapshot) == REGISTRY_BEACON_PROXY_MECHANISM) {
                count++;
            }
        }
        assertEq(count, v6.length, "one suite per V6 row");
        TokenConfig[] memory production = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 i = 0; i < production.length; i++) {
            if (bytes(production[i].assetId).length == 0) {
                (, bool found) = candidateOf(declared, string.concat(TOKEN_PREFIX, lowercase(production[i].symbol)));
                assertFalse(found, production[i].underlying);
            }
        }
    }
}
