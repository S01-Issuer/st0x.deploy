// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {
    DeployDeclaration,
    DeploySuite,
    UnknownDeploymentSuite
} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {Deploy} from "../../script/Deploy.sol";
import {TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";

contract DeployPreDeployCheckHarness is Deploy {
    function governanceTimelockSuite() external view returns (DeploySuite memory) {
        return suiteByName(declaration(), GOVERNANCE_TIMELOCK);
    }

    function beaconSuites() external view returns (DeploySuite[] memory) {
        DeployDeclaration memory declared = declaration();
        string[] memory names = beaconOwnerSuites();
        DeploySuite[] memory suites = new DeploySuite[](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            suites[i] = suiteByName(declared, names[i]);
        }
        return suites;
    }

    function declaredTokenSuites(TokenConfig[] memory configs) external view returns (DeploySuite[] memory) {
        return declaredSuites(configs, "");
    }

    function declaredWrapperSuites(TokenConfig[] memory configs) external view returns (DeploySuite[] memory) {
        return declaredSuites(configs, WRAPPER_SUFFIX);
    }

    function declaredSuites(TokenConfig[] memory configs, string memory suffix)
        internal
        view
        returns (DeploySuite[] memory)
    {
        DeployDeclaration memory declared = declaration();
        DeploySuite[] memory all = allSuites(declared);
        DeploySuite[] memory suites = new DeploySuite[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            string memory name = string.concat(tokenSuiteName(configs[i]), suffix);
            uint256 index = suiteIndex(all, name);
            if (index == all.length) {
                revert UnknownDeploymentSuite(name, suiteNames(declared));
            }
            suites[i] = all[index];
        }
        return suites;
    }

    function checkedSuiteNames(TokenConfig[] memory configs) external pure returns (string[] memory) {
        string[] memory beacons = beaconOwnerSuites();
        uint256 head = 1 + beacons.length;
        string[] memory names = new string[](head + 2 * configs.length);
        names[0] = GOVERNANCE_TIMELOCK;
        for (uint256 i = 0; i < beacons.length; i++) {
            names[1 + i] = beacons[i];
        }
        for (uint256 i = 0; i < configs.length; i++) {
            names[head + 2 * i] = tokenSuiteName(configs[i]);
            names[head + 1 + 2 * i] = string.concat(tokenSuiteName(configs[i]), WRAPPER_SUFFIX);
        }
        return names;
    }

    function tokenSuiteName(TokenConfig memory config) internal pure returns (string memory) {
        return string.concat(TOKEN_PREFIX, lowercase(config.symbol));
    }

    function deployNetworkConfigs() external view returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(declaration().deployNetworks);
    }

    function exposedPreDeployCheck(DeploySuite memory suite, SupportedNetwork memory network) external view {
        preDeployCheck(declaration(), suite, network);
    }
}
