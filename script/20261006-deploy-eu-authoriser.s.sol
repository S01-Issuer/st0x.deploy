// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {ICloneableFactoryV4} from "rain-factory-0.1.30/src/interface/ICloneableFactoryV4.sol";
import {LibCloneFactoryDeploy} from "rain-factory-deploy-0.1.15/src/lib/LibCloneFactoryDeploy.sol";
import {LibRainDeploy} from "rain-deploy-0.1.15/src/lib/LibRainDeploy.sol";

import {EuAuthoriserDeploySuites} from "../src/abstract/EuAuthoriserDeploySuites.sol";
import {EU_AUTHORISER_SALT, LibEuAuthoriserClone} from "../src/lib/LibEuAuthoriserClone.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The clone factory is not deployed, or does not carry the pinned
/// codehash, on the active chain.
/// @param factory The factory address inspected.
error EuCloneFactoryNotReady(address factory);

/// @notice The factory returned an address other than the one it predicted.
/// @param predicted The address the declaration carries.
/// @param deployed The address the clone landed at.
error EuCloneAddressMismatch(address predicted, address deployed);

/// @title DeployEuAuthoriser
/// @notice Clones the audited 0.1.1 authoriser at its open-salt address, one
/// address on every network.
///
/// `RainDeployBroadcast` is NOT the base here, and the reason is the clone: it
/// broadcasts a suite's creation code through the Zoltu factory, which would
/// put the proxy at a Zoltu-derived address with no record in the clone
/// factory. The address this repo wants is the clone factory's own open-salt
/// derivation, so the broadcast is that factory call. Everything else comes
/// from the package: the declaration is `EuAuthoriserDeploySuites` and the
/// addresses and code hashes are `LibEuAuthoriserClone`'s derivations of
/// `rain-factory`'s own helpers. The networks are this repo's, not the
/// package's — see `supportedNetworks` below.
///
/// Idempotent: a clone already at the predicted address is left alone, so a
/// re-dispatch after a partial rollout only fills in the networks still
/// missing it.
contract DeployEuAuthoriser is EuAuthoriserDeploySuites, Script {
    /// @notice Deploys the clone to EVERY supported network that lacks it, in
    /// one dispatch.
    ///
    /// All networks every time, because the deploy is idempotent: the open
    /// salt puts one address everywhere, and a network already holding the
    /// clone is skipped. A dispatch is then a statement about the whole fleet
    /// rather than about whichever chain the runner selected, which is how
    /// `LibRainDeploy.deployToNetworks` behaves.
    ///
    /// The networks come from the inherited `supportedNetworks()` hook, so a
    /// narrowed dispatch overrides that rather than editing this loop.
    ///
    /// Every fork is created before any is selected, for the reason that
    /// library gives: an unreachable or rate-limited endpoint takes the whole
    /// run up front instead of stopping partway with some networks deployed
    /// and some not.
    function run() external {
        string[] memory networks = supportedNetworks();
        address clone = LibEuAuthoriserClone.cloneDeployedAddress();
        address implementation = LibEuAuthoriserClone.implementation();
        bytes memory data = LibEuAuthoriserClone.cloneData();
        address factory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;

        uint256[] memory forkIds = LibRainDeploy.createForks(vm, networks);

        // Every network's factory is checked before any network is broadcast
        // to, for the same reason every fork is created before any is
        // selected: a factory missing on the last network would otherwise be
        // found after the first four had already deployed, leaving the
        // rollout half done and the refusal describing a state that no longer
        // matches the chains.
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            if (factory.code.length == 0 || factory.codehash != LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH) {
                revert EuCloneFactoryNotReady(factory);
            }
        }

        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            console2.log("Network:", networks[i]);
            console2.log("Block number:", block.number);

            if (clone.code.length == 0) {
                vm.startBroadcast();
                address deployed =
                    ICloneableFactoryV4(factory).cloneDeterministicOpenSalt(implementation, data, EU_AUTHORISER_SALT);
                vm.stopBroadcast();
                if (deployed != clone) revert EuCloneAddressMismatch(clone, deployed);
                console2.log("Deployed.");
            } else {
                console2.log("Already deployed, skipped.");
            }

            console2.log("Admin holder for the seven _ADMIN roles:");
            console2.log(vm.toString(LibTimelockInvariants.timelockForChainId(block.chainid)));
        }

        console2.log("EU assets authoriser:", vm.toString(clone));
        console2.log("Minter to be granted DEPOSIT and WITHDRAW (mint and redeem):");
        console2.log(vm.toString(LibAuthoriserInvariants.GRANTEE_EU_MINTER));
    }
}
