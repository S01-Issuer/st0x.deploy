// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {DeployDependency} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V8_ADDRESS,
    RUNTIME_CODE as CLONE_FACTORY_V8_RUNTIME_CODE
} from "rain-factory-deploy-0.2.6/src/generated/0_2_5/CloneFactory.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibProdDeployV4 as V4} from "../../../src/generated/LibProdDeployV4.sol";

/// @title StoxDeploySuitesReceiptVaultDependenciesTest
/// @notice The receipt vault candidate depends on the facet, registry and V8 clone factory.
contract StoxDeploySuitesReceiptVaultDependenciesTest is Test, StoxDeploySuites {
    function testReceiptVaultCandidateDependsOnTheFacetRegistryAndV8Factory() external view {
        (DeploySuite memory suite, bool found) = candidateOf(declaration(), RECEIPT_VAULT);
        assertTrue(found, RECEIPT_VAULT);
        DeployDependency[] memory deps = suite.dependencies;
        assertEq(deps.length, 3, "dependencies");
        assertEq(deps[0].deployedAddress, V4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, "facet address");
        assertEq(deps[0].runtimeCode, V4.STOX_CORPORATE_ACTIONS_FACET_RUNTIME_CODE_CANDIDATE, "facet code");
        assertEq(deps[1].deployedAddress, CONFIG_REGISTRY_ADDRESS, "registry address");
        assertEq(deps[1].runtimeCode, CONFIG_REGISTRY_RUNTIME_CODE, "registry code");
        assertEq(deps[2].deployedAddress, CLONE_FACTORY_V8_ADDRESS, "factory address");
        assertEq(deps[2].runtimeCode, CLONE_FACTORY_V8_RUNTIME_CODE, "factory code");
    }
}
