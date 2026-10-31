// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifySnapshot} from "rain-deploy-0.1.29/src/abstract/RainDeployVerifySnapshot.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

contract StoxDeploySnapshotTest is StoxDeploySuites, RainDeployVerifySnapshot {
    /// The orchestrator beacon-set deployer's constructor resolves the
    /// governance timelock; its bytecode does not depend on the bound value,
    /// as in `script/BuildPointers.sol`.
    function setUp() external {
        LibTestDeploy.bindGovernanceTimelock(vm, makeAddr("timelock"));
    }
}
