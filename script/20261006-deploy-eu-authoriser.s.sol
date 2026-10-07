// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {ICloneableFactoryV4} from "rain-factory-0.1.30/src/interface/ICloneableFactoryV4.sol";
import {LibCloneFactoryDeploy} from "rain-factory-deploy-0.1.15/src/lib/LibCloneFactoryDeploy.sol";

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
/// from the package: the declaration is `EuAuthoriserDeploySuites`, the
/// addresses and code hashes are `LibEuAuthoriserClone`'s derivations of
/// `rain-factory`'s own helpers, and the networks are `LibRainDeploy`'s.
///
/// Idempotent: a clone already at the predicted address is left alone, so a
/// re-dispatch after a partial rollout only fills in the networks still
/// missing it.
contract DeployEuAuthoriser is EuAuthoriserDeploySuites, Script {
    /// @notice Deploys the clone where it is missing, then reports what still
    /// has to be granted on it.
    function run() external {
        address factory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        if (factory.code.length == 0 || factory.codehash != LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH) {
            revert EuCloneFactoryNotReady(factory);
        }

        address clone = LibEuAuthoriserClone.cloneDeployedAddress();

        if (clone.code.length == 0) {
            vm.startBroadcast();
            address deployed = ICloneableFactoryV4(factory)
                .cloneDeterministicOpenSalt(
                    LibEuAuthoriserClone.implementation(), LibEuAuthoriserClone.cloneData(), EU_AUTHORISER_SALT
                );
            vm.stopBroadcast();
            if (deployed != clone) revert EuCloneAddressMismatch(clone, deployed);
        }

        console2.log("EU assets authoriser:", vm.toString(clone));
        console2.log("Chain:", block.chainid);
        console2.log("Minter to be granted DEPOSIT and WITHDRAW (mint and redeem):");
        console2.log(vm.toString(LibAuthoriserInvariants.GRANTEE_EU_MINTER));
        console2.log("Admin holder for the seven _ADMIN roles:");
        console2.log(vm.toString(LibTimelockInvariants.timelockForChainId(block.chainid)));
    }
}
