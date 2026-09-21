// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "rain-deploy-0.1.11/src/abstract/RainDeployBroadcast.sol";
import {StoxDeploySuites} from "../src/abstract/StoxDeploySuites.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";

/// @title Deploy
/// @notice Broadcasts the suite `DEPLOYMENT_SUITE` names to every network ST0x
/// deploys to. A frozen release is selected by its key with the release tag
/// appended, and deploys that release's stored creation code, whatever
/// current source compiles to.
contract Deploy is StoxDeploySuites, RainDeployBroadcast {
    /// @inheritdoc RainDeployBroadcast
    function deployNetworks() internal pure override returns (string[] memory) {
        return LibStoxDeployNetworks.deploymentNetworks();
    }
}
