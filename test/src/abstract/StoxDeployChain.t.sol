// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifyChain} from "rain-deploy-0.1.29/src/abstract/RainDeployVerifyChain.sol";
import {RainDeploySuitesBase} from "rain-deploy-0.1.29/src/abstract/RainDeploySuitesBase.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";

contract StoxDeployChainTest is StoxDeploySuites, RainDeployVerifyChain {
    function supportedNetworks()
        internal
        view
        override(StoxDeploySuites, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return StoxDeploySuites.supportedNetworks();
    }
}
