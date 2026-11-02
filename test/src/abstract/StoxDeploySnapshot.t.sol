// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifySnapshot} from "rain-deploy-0.1.29/src/abstract/RainDeployVerifySnapshot.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS} from "rain-deploy-0.1.29/src/generated/0_1_29/ConfigRegistry.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

contract StoxDeploySnapshotTest is StoxDeploySuites, RainDeployVerifySnapshot {
    /// The beacon's constructor reads its owner from the registry; the bound
    /// value is storage, not code. The registry code goes again so only a
    /// suite's declared dependency etches it back.
    function setUp() public {
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bind(
            vm, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.GOVERNANCE_TIMELOCK_NAME, "address", abi.encode(address(1))
        );
        vm.etch(CONFIG_REGISTRY_ADDRESS, hex"");
    }
}
