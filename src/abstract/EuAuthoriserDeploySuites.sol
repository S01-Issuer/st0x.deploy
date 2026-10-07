// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeploySuite,
    RainDeploySuitesBase
} from "rain-deploy-0.1.15/src/abstract/RainDeploySuitesBase.sol";

import {LibStoxDeployNetworks} from "../lib/LibStoxDeployNetworks.sol";

/// @title EuAuthoriserDeploySuites
/// @notice The networks the EU assets authoriser deploys to, shared by the
/// deploy script and the chain-matrix verification so the two cannot disagree.
///
/// The clone itself declares no suite. Its init data carries the chain's own
/// token-owner Safe as initial admin, so its address is per-chain, and
/// `candidateSuites` is `pure` in the base — it cannot read `block.chainid`,
/// so it cannot carry a per-chain address. The deploy script derives the
/// address per fork instead.
abstract contract EuAuthoriserDeploySuites is RainDeploySuitesBase {
    /// @inheritdoc RainDeploySuitesBase
    /// @dev The networks THIS repo deploys to, not the package's default nine.
    /// arbitrum, polygon, flare and base sepolia carry no ST0x deployment.
    function supportedNetworks() internal view virtual override returns (string[] memory) {
        return LibStoxDeployNetworks.deploymentNetworks();
    }

    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory) {
        return new DeployCandidate[](0);
    }
}
