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
import {LibProdTokenConfig, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";

contract DeployPreDeployCheckHarness is Deploy {
    function governanceTimelockSuite() external view returns (DeploySuite memory) {
        return suiteByName(declaration(), GOVERNANCE_TIMELOCK);
    }

    function declaredSuite(string memory name) external view returns (DeploySuite memory) {
        return suiteByName(declaration(), name);
    }

    function beaconSuites() external view returns (DeploySuite[] memory) {
        DeployDeclaration memory declared = declaration();
        DeploySuite[] memory suites = new DeploySuite[](3);
        suites[0] = suiteByName(declared, RECEIPT_BEACON);
        suites[1] = suiteByName(declared, RECEIPT_VAULT_BEACON);
        suites[2] = suiteByName(declared, WRAPPED_TOKEN_VAULT_BEACON);
        return suites;
    }

    function declaredTokenSuites(TokenConfig[] memory configs) external view returns (DeploySuite[] memory) {
        DeployDeclaration memory declared = declaration();
        DeploySuite[] memory all = allSuites(declared);
        DeploySuite[] memory suites = new DeploySuite[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            string memory name = tokenSuiteName(configs[i]);
            uint256 index = suiteIndex(all, name);
            if (index == all.length) {
                revert UnknownDeploymentSuite(name, suiteNames(declared));
            }
            suites[i] = all[index];
        }
        return suites;
    }

    function checkedSuiteNames() external pure returns (string[] memory) {
        TokenConfig[] memory production = LibProdTokenConfig.productionTokenConfigs();
        TokenConfig[] memory test = LibProdTokenConfig.testTokenConfigs();
        string[] memory names = new string[](4 + production.length + 2 * test.length);
        names[0] = GOVERNANCE_TIMELOCK;
        names[1] = RECEIPT_BEACON;
        names[2] = RECEIPT_VAULT_BEACON;
        names[3] = WRAPPED_TOKEN_VAULT_BEACON;
        for (uint256 i = 0; i < production.length; i++) {
            names[4 + i] = tokenSuiteName(production[i]);
        }
        for (uint256 i = 0; i < test.length; i++) {
            names[4 + production.length + 2 * i] = tokenSuiteName(test[i]);
            names[5 + production.length + 2 * i] = string.concat(tokenSuiteName(test[i]), WRAPPER_SUFFIX);
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
