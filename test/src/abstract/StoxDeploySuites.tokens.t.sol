// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.29/src/abstract/RainDeploySuitesBase.sol";
import {REGISTRY_BEACON_PROXY_MECHANISM} from "rain-factory-0.2.9/src/lib/LibRainDeployCloneMechanism.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";

/// @title StoxDeploySuitesTokensTest
/// @notice No token is a deploy suite.
contract StoxDeploySuitesTokensTest is Test, StoxDeploySuites {
    function testNoSuiteIsARegistryBeaconProxy() external view {
        DeployDeclaration memory declared = declaration();
        for (uint256 i = 0; i < declared.released.length; i++) {
            assertNotEq(
                mechanismIdOf(declared.released[i]), REGISTRY_BEACON_PROXY_MECHANISM, declared.released[i].suite
            );
        }
        for (uint256 i = 0; i < declared.candidates.length; i++) {
            DeploySuite memory snapshot = declared.candidates[i].snapshot;
            assertNotEq(mechanismIdOf(snapshot), REGISTRY_BEACON_PROXY_MECHANISM, snapshot.suite);
        }
    }
}
