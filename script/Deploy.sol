// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "rain-deploy-0.1.30/src/abstract/RainDeployBroadcast.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {StoxDeploySuites} from "../src/abstract/StoxDeploySuites.sol";
import {LibStoxConfig} from "../src/lib/LibStoxConfig.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";

error TimelockInitialProposerMismatch(address bound, address expected);

/// @title Deploy
/// @notice `RainDeployBroadcast` over `StoxDeploySuites`: broadcasts the suite
/// `DEPLOYMENT_SUITE` names to every network this repo deploys to.
contract Deploy is StoxDeploySuites, RainDeployBroadcast {
    /// The timelock proposer is the registry binding, so it must be this chain's Safe.
    function preDeployCheck(DeployDeclaration memory, DeploySuite memory suite, SupportedNetwork memory)
        internal
        view
        override
    {
        if (keccak256(bytes(suite.suite)) == keccak256(bytes(GOVERNANCE_TIMELOCK))) {
            address bound = LibStoxConfig.timelockInitialProposer();
            address expected = LibSafeInvariants.safeForChainId(block.chainid);
            if (bound != expected) {
                revert TimelockInitialProposerMismatch(bound, expected);
            }
        }
    }
}
