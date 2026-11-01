// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifyChain} from "rain-deploy-0.1.29/src/abstract/RainDeployVerifyChain.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxTokenBindings} from "../../../src/lib/LibStoxTokenBindings.sol";

contract StoxDeployChainTest is StoxDeploySuites, RainDeployVerifyChain {
    function testTokenBindingsResolveToTheDeclarationOnEveryNetwork() external {
        LibStoxTokenBindings.checkOnNetworks(vm, LibStoxDeployNetworks.deploymentNetworks(), vaultBeacon());
    }
}
