// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {
    LibRainDeployCloneMechanism,
    REGISTRY_BEACON_PROXY_MECHANISM
} from "rain-factory-0.2.11/src/lib/LibRainDeployCloneMechanism.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";

/// @title StoxDeploySuitesProductionTokenSuitesTest
/// @notice The production declaration has a token suite for each V6 row and each test token only.
contract StoxDeploySuitesProductionTokenSuitesTest is Test, StoxDeploySuites {
    function testOnlyV6RowsAreDeclaredTokenSuites() external view {
        DeployDeclaration memory declared = declaration();
        TokenConfig[] memory v6 = LibProdTokenConfig.v6TokenConfigs();
        uint256 count = 0;
        for (uint256 i = 0; i < declared.candidates.length; i++) {
            if (
                mechanismIdOf(declared.candidates[i].snapshot) == REGISTRY_BEACON_PROXY_MECHANISM
                    && LibRainDeployCloneMechanism.registryBeaconProxyParams(declared.candidates[i].snapshot).beaconName
                        == LibStoxConfig.VAULT_BEACON_NAME
            ) {
                count++;
            }
        }
        assertEq(count, v6.length + LibProdTokenConfig.testTokenConfigs().length, "one suite per V6 and test row");
        for (uint256 i = 0; i < v6.length; i++) {
            (, bool found) = candidateOf(declared, string.concat(TOKEN_PREFIX, lowercase(v6[i].symbol)));
            assertTrue(found, v6[i].underlying);
        }
    }

    /// A row with an empty asset id gets no token suite, whatever the live table holds.
    function testRowWithoutAssetIdGetsNoTokenSuite() external pure {
        TokenConfig[] memory rows = LibProdTokenConfig.productionTokenConfigs();
        rows[0].assetId = "";
        TokenConfig[] memory v6 = LibProdTokenConfig.withAssetId(rows);
        assertEq(v6.length, rows.length - 1, "one row dropped");
        for (uint256 i = 0; i < v6.length; i++) {
            assertNotEq(keccak256(bytes(v6[i].underlying)), keccak256(bytes(rows[0].underlying)), v6[i].underlying);
        }
    }
}
