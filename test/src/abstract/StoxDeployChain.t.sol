// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifyChain} from "rain-deploy-0.1.30/src/abstract/RainDeployVerifyChain.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

contract StoxDeployChainTest is StoxDeploySuites, RainDeployVerifyChain {
    /// Released suites derive on this bare EVM before any fork, and a released
    /// timelock's constructor resolves the governance Safe. The registry code
    /// goes again so only a suite's declared dependency etches it back.
    function setUp() external {
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.TIMELOCK_INITIAL_PROPOSER_NAME,
            "address",
            abi.encode(address(0x5AFE))
        );
        vm.etch(CONFIG_REGISTRY_ADDRESS, hex"");
    }
}
