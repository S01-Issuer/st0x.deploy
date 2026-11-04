// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {Deploy} from "../../script/Deploy.sol";

contract DeployPreDeployCheckHarness is Deploy {
    function governanceTimelockSuite() external view returns (DeploySuite memory) {
        return suiteByName(declaration(), GOVERNANCE_TIMELOCK);
    }

    function deployNetworkConfigs() external view returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(declaration().deployNetworks);
    }

    function exposedPreDeployCheck(DeploySuite memory suite, SupportedNetwork memory network) external view {
        preDeployCheck(declaration(), suite, network);
    }
}
