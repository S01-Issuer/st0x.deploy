// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "rain-deploy-0.1.30/src/abstract/RainDeployBroadcast.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {StoxDeploySuites} from "../src/abstract/StoxDeploySuites.sol";
import {LibStoxConfig} from "../src/lib/LibStoxConfig.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibProdDeployCurrent} from "../src/generated/LibProdDeployCurrent.sol";

error GovernanceSafeMismatch(address bound, address expected);
error AuthoriserInitialAdminMismatch(address bound, address expected);

/// @title Deploy
/// @notice `RainDeployBroadcast` over `StoxDeploySuites`: broadcasts the suite
/// `DEPLOYMENT_SUITE` names to every network this repo deploys to.
contract Deploy is StoxDeploySuites, RainDeployBroadcast {
    /// The timelock proposer and the authoriser initial admin are registry
    /// bindings, so each must be its expected account on this chain.
    function preDeployCheck(DeployDeclaration memory, DeploySuite memory suite, SupportedNetwork memory)
        internal
        view
        override
    {
        if (keccak256(bytes(suite.suite)) == keccak256(bytes(GOVERNANCE_TIMELOCK))) {
            address bound = LibStoxConfig.governanceSafe();
            address expected = LibSafeInvariants.safeForChainId(block.chainid);
            if (bound != expected) {
                revert GovernanceSafeMismatch(bound, expected);
            }
        } else if (keccak256(bytes(suite.suite)) == keccak256(bytes(AUTHORISER))) {
            address bound = LibStoxConfig.authoriserInitialAdmin();
            address expected = LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK;
            if (bound != expected) {
                revert AuthoriserInitialAdminMismatch(bound, expected);
            }
        }
    }
}
