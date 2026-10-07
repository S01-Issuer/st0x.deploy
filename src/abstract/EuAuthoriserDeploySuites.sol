// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeploySuite,
    RainDeploySuitesBase
} from "rain-deploy-0.1.15/src/abstract/RainDeploySuitesBase.sol";
import {DeployDependency} from "rain-deploy-0.1.15/src/lib/LibRainDeploy.sol";

import {LibEuAuthoriserClone} from "../lib/LibEuAuthoriserClone.sol";
import {LibStoxDeployNetworks} from "../lib/LibStoxDeployNetworks.sol";

/// @title EuAuthoriserDeploySuites
/// @notice The EU assets authoriser as a `rain-deploy` declaration, so the
/// cross-chain checks the package already ships apply to it.
///
/// The clone is UNANCHORABLE: an EIP-1167 minimal proxy is assembled by the
/// clone factory from the implementation address, so no source file in this
/// repo compiles to it and `checkCandidatesAnchoredToSource` would have
/// nothing to compare. That is the category `unanchorableReason` exists for,
/// and stating it is what makes the declaration legal rather than a hole.
///
/// The implementation it proxies IS anchored — audited, deployed, and pinned
/// in `LibProdDeployV4` — which is the point of cloning rather than compiling
/// a second authoriser.
abstract contract EuAuthoriserDeploySuites is RainDeploySuitesBase {
    /// @inheritdoc RainDeploySuitesBase
    /// @dev The networks THIS repo deploys to, not the package's default nine.
    /// It is declared here rather than on the deploy script so the script and
    /// the chain-matrix verification cannot disagree: a narrower deploy than
    /// the declaration would leave the matrix asserting the clone live on
    /// chains nothing ever deployed it to. arbitrum, polygon, flare and base
    /// sepolia carry no ST0x deployment at all.
    function supportedNetworks() internal view virtual override returns (string[] memory) {
        return LibStoxDeployNetworks.deploymentNetworks();
    }

    /// @inheritdoc RainDeploySuitesBase
    /// @dev Nothing released: the clone is deployed by the factory, not frozen
    /// into this repo's record, so there is no released suite to describe.
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    /// @dev No declared dependency, because the implementation address is
    /// embedded in the proxy's own runtime: a clone whose code hash matches
    /// cannot be delegating anywhere else, so the hash check already covers
    /// what a dependency entry would restate.
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "eu-assets-authoriser",
                creationCode: LibEuAuthoriserClone.cloneCreationCode(),
                storedDeployedAddress: LibEuAuthoriserClone.cloneDeployedAddress(),
                storedBytecodeHash: LibEuAuthoriserClone.cloneDeployedCodehash(),
                storedRuntimeCode: LibEuAuthoriserClone.cloneRuntimeCode(),
                artifactPath: "",
                dependencies: new DeployDependency[](0)
            }),
            unanchorableReason: "An EIP-1167 minimal proxy, assembled by the clone factory from the "
            "implementation address. No compiler produces it, so there is no artifact to anchor "
            "it to; the implementation it delegates into is the anchored contract."
        });
    }
}
