// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {
    DeployDeclaration,
    DeploySuite,
    UnknownDeploymentSuite
} from "rain-deploy-0.1.38/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {Deploy} from "../../script/Deploy.sol";
import {TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";

contract DeployPreDeployCheckHarness is Deploy {
    /// @dev The run's suite. `vm.setEnv` is process-wide, so the harness does
    /// not read `DEPLOYMENT_SUITE` unless a test asks it to: a test running in
    /// parallel that sets it cannot reach another test's declaration.
    string internal sRequestedSuite;
    bool internal sRequestedSuiteFromEnv;

    function setRequestedSuite(string memory suite) external {
        sRequestedSuite = suite;
    }

    /// @dev From now on the run's suite is `Deploy`'s own `DEPLOYMENT_SUITE` read.
    function readRequestedSuiteFromEnv() external {
        sRequestedSuiteFromEnv = true;
    }

    function requestedSuite() internal view override returns (string memory) {
        return sRequestedSuiteFromEnv ? super.requestedSuite() : sRequestedSuite;
    }

    function governanceTimelockSuite() external view returns (DeploySuite memory) {
        return suiteByName(declaration(), GOVERNANCE_TIMELOCK);
    }

    function beaconSuites() external view returns (DeploySuite[] memory) {
        DeployDeclaration memory declared = declaration();
        DeploySuite[] memory suites = new DeploySuite[](4);
        suites[0] = suiteByName(declared, RECEIPT_BEACON);
        suites[1] = suiteByName(declared, RECEIPT_VAULT_BEACON);
        suites[2] = suiteByName(declared, WRAPPED_TOKEN_VAULT_BEACON);
        suites[3] = suiteByName(declared, ORCHESTRATOR_BEACON);
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
        string[] memory names = new string[](5 + 2 * configs.length);
        names[0] = GOVERNANCE_TIMELOCK;
        names[1] = RECEIPT_BEACON;
        names[2] = RECEIPT_VAULT_BEACON;
        names[3] = WRAPPED_TOKEN_VAULT_BEACON;
        names[4] = ORCHESTRATOR_BEACON;
        for (uint256 i = 0; i < configs.length; i++) {
            names[5 + 2 * i] = tokenSuiteName(configs[i]);
            names[6 + 2 * i] = string.concat(tokenSuiteName(configs[i]), WRAPPER_SUFFIX);
        }
        return names;
    }

    function tokenSuiteName(TokenConfig memory config) internal pure returns (string memory) {
        return string.concat(TOKEN_PREFIX, lowercase(config.symbol));
    }

    function deployNetworkConfigs() external view returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(declaration().deployNetworks);
    }

    /// @dev The networks a run that names `suite` deploys to.
    function deployNetworkConfigsFor(string memory suite) external view returns (SupportedNetwork[] memory) {
        DeployDeclaration memory declared = declaration();
        narrowToSuite(declared, suite);
        return LibRainDeploy.declaredNetworkConfigs(declared.deployNetworks);
    }

    function exposedPreDeployCheck(DeploySuite memory suite, SupportedNetwork memory network) external view {
        preDeployCheck(declaration(), suite, network);
    }
}
