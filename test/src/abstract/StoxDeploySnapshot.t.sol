// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifySnapshot} from "rain-deploy-0.1.29/src/abstract/RainDeployVerifySnapshot.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibStoxConfigFork} from "../../../src/lib/LibStoxConfigFork.sol";

contract StoxDeploySnapshotTest is StoxDeploySuites, RainDeployVerifySnapshot {
    /// The beacon's constructor reads its owner from the registry; the bound
    /// value is storage, not code.
    function setUp() public {
        LibStoxConfigFork.bindBeaconOwner(vm, address(1));
    }
}
