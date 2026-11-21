// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeploySuite} from "rain-deploy-0.1.38/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "rain-deploy-0.1.38/src/lib/LibRainDeployDeclaration.sol";
import {LibReleasedSuites} from "./LibReleasedSuites.sol";
import {LibStoxDeployNetworks} from "./LibStoxDeployNetworks.sol";

/// @notice A key `LibStoxReleasedNetworks.releasesNotOnZerog` names matches no
/// frozen release, so the narrowing it asks for would silently not happen.
/// @param suite The key.
error ReleaseNotOnZerogUnknown(string suite);

/// @title LibStoxReleasedNetworks
/// @notice The networks each frozen release is required on. `addReleased`
/// requires a release that names no networks on every `deploymentNetworks()`
/// entry, 0G included. 0G runs the audited 0.1.1 and 0.1.30 sets, so every
/// release cut so far is required there except the ones `releasesNotOnZerog`
/// names. Those stay on `networksBeforeZerog()`, the networks they were cut
/// and deployed for.
library LibStoxReleasedNetworks {
    /// @notice Every frozen release, each 0G does not run narrowed to
    /// `LibStoxDeployNetworks.networksBeforeZerog()`.
    /// @return The releases, in `LibReleasedSuites` order.
    function releasedSuites() internal pure returns (DeploySuite[] memory) {
        return offZerog(LibReleasedSuites.releasedSuites(), releasesNotOnZerog());
    }

    /// @notice `released`, each of `notOnZerog` narrowed to
    /// `LibStoxDeployNetworks.networksBeforeZerog()`. Refuses
    /// `ReleaseNotOnZerogUnknown` for a key no release has. Suite keys are
    /// unique, so each key narrows one release.
    /// @param released The releases, mutated.
    /// @param notOnZerog The keys of the releases 0G does not run.
    /// @return `released`.
    function offZerog(DeploySuite[] memory released, string[] memory notOnZerog)
        internal
        pure
        returns (DeploySuite[] memory)
    {
        for (uint256 i = 0; i < notOnZerog.length; i++) {
            uint256 index = LibRainDeployDeclaration.suiteIndex(released, notOnZerog[i]);
            if (index == released.length) revert ReleaseNotOnZerogUnknown(notOnZerog[i]);
            released[index].networks = LibStoxDeployNetworks.networksBeforeZerog();
        }
        return released;
    }

    /// @notice The frozen releases 0G does not run.
    /// @return The release suite keys.
    function releasesNotOnZerog() internal pure returns (string[] memory) {
        string[] memory suites = new string[](2);
        // No 0G token mints through a payment-mint authoriser.
        suites[0] = "stox-offchain-asset-receipt-vault-payment-mint-authorizer@0_1_1";
        // Its `deploy(owner)` is permissionless, and its first call creates the
        // orchestrator at its pinned address on every chain. Deployed on 0G, it
        // would let anyone take that address and its admin. A reviewed 0G
        // orchestrator migration deploys it and claims the instance for the 0G
        // timelock in one step. Without it, 0G has no orchestrator beacon
        // (`LibBeaconInvariants.prodBeaconsInUse`). Its 0.1.30 implementation
        // is harmless alone and stays required on 0G.
        suites[1] = "stox-orchestrator-beacon-set-deployer@0_1_30";
        return suites;
    }
}
