// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "rain-deploy-0.1.29/src/abstract/RainDeployBroadcast.sol";
import {StoxDeploySuites} from "../src/abstract/StoxDeploySuites.sol";

/// @title Deploy
/// @notice `RainDeployBroadcast` over `StoxDeploySuites`: broadcasts the suite
/// `DEPLOYMENT_SUITE` names to every network this repo deploys to.
contract Deploy is StoxDeploySuites, RainDeployBroadcast {}
