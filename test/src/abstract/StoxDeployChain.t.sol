// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifyChain} from "rain-deploy-0.1.29/src/abstract/RainDeployVerifyChain.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

contract StoxDeployChainTest is StoxDeploySuites, RainDeployVerifyChain {
    /// The beacon's constructor reads its owner from the registry; the bound
    /// value is storage, not code.
    function setUp() public {
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bind(
            vm, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.GOVERNANCE_TIMELOCK_NAME, "address", abi.encode(address(1))
        );
    }
}
