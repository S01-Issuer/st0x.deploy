// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {LibCloneFactoryDeploy} from "rain-factory-0.1.1/src/lib/LibCloneFactoryDeploy.sol";

/// @notice The CloneFactory pin already has code on this chain: nothing to
/// deploy (a re-dispatch), or something else occupies the address.
/// @param factory The pinned address.
error CloneFactoryAlreadyDeployed(address factory);

/// @notice The Zoltu factory is not at its canonical address on this chain,
/// so the deterministic deploy cannot land at the pin.
/// @param zoltu The canonical Zoltu factory address.
error ZoltuFactoryMissing(address zoltu);

/// @notice The Zoltu deploy of the frozen creation code landed somewhere
/// other than the pin — the creation code below is not the one that produced
/// the pin.
/// @param expected The pinned CloneFactory address.
/// @param actual Where the deploy landed.
error CloneFactoryLandedElsewhere(address expected, address actual);

/// @notice The deployed runtime's codehash is not the pinned codehash.
/// @param expected The pinned codehash.
/// @param actual The deployed codehash.
error CloneFactoryCodehashMismatch(bytes32 expected, bytes32 actual);

/// @title DeployCloneFactory
/// @notice Deploys the rain-factory 0.1.1 `CloneFactory` — the one this repo
/// pins (`LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS`, `0x444acC…`)
/// and the one `20260619-deploy-v4-authoriser-clone` refuses to run without —
/// onto a newly onboarded chain, through the Zoltu factory at its canonical
/// address, from the frozen creation code below. Same bytes, same salt-free
/// derivation, same address on every chain.
///
/// @dev Why this lives here and not in the Rain org: `rainlanguage/rain.factory.deploy`
/// ships the CURRENT `CloneFactory` release (0.1.9 / 0.1.10, at `0xAb9741E6…`).
/// This repo's authoriser clones on Base, Ethereum and HyperEVM were all made
/// through the 0.1.1 factory at `0x444acC…`, and every chain's authoriser must
/// come from the same factory for the pinned-address story to hold, so the
/// 0.1.1 factory is what a new chain needs. Its creation code is no longer
/// published by any Rain deploy repo; it is carried here, frozen, and proven
/// against the pin on every run (address AND codehash), so a drifted literal
/// cannot deploy anything.
///
/// Dispatch via `Actions → manual-broadcast` with
/// `script = 20260910-deploy-clone-factory` and `network` set to the new
/// chain. Self-scoping: refuses a chain whose pin already has code, and a
/// chain without the Zoltu factory. Any funded key can send it; the address
/// does not depend on the sender.
contract DeployCloneFactory is Script {
    /// @notice The rain-factory 0.1.1 `CloneFactory` creation code, frozen.
    /// Reproduces `CLONE_FACTORY_DEPLOYED_ADDRESS` through Zoltu on every
    /// chain (`testFrozenCreationCodeReproducesThePin`).
    bytes internal constant CLONE_FACTORY_0_1_1_CREATION_CODE =
        hex"6080604052348015600e575f80fd5b506103f48061001c5f395ff3fe608060405234801561000f575f80fd5b5060043610610029575f3560e01c80630fbe133c1461002d575b5f80fd5b61004061003b3660046102fb565b610069565b60405173ffffffffffffffffffffffffffffffffffffffff909116815260200160405180910390f35b5f8373ffffffffffffffffffffffffffffffffffffffff163b5f036100ba576040517ff432283200000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b5f6100c485610213565b6040805133815273ffffffffffffffffffffffffffffffffffffffff888116602083015283168183015290519192507f274b5f356634f32a865af65bdc3d8205939d9413d75e1f367652e4f3b24d0c3a919081900360600190a16040517f439fab910000000000000000000000000000000000000000000000000000000081527fe0e57eda3f08f2a93bbe980d3df7f9c315eac41181f58b865a13d917fe769fc39073ffffffffffffffffffffffffffffffffffffffff83169063439fab91906101949088908890600401610391565b6020604051808303815f875af11580156101b0573d5f803e3d5ffd5b505050506040513d601f19601f820116820180604052508101906101d491906103dd565b1461020b576040517f19b991a800000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b949350505050565b5f61021e825f610224565b92915050565b5f8147101561026c576040517fcf4791810000000000000000000000000000000000000000000000000000000081524760048201526024810183905260440160405180910390fd5b763d602d80600a3d3981f3363d3d373d3d3d363d730000008360601b60e81c175f526e5af43d82803e903d91602b57fd5bf38360781b176020526037600983f0905073ffffffffffffffffffffffffffffffffffffffff811661021e576040517fb06ebf3d00000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b5f805f6040848603121561030d575f80fd5b833573ffffffffffffffffffffffffffffffffffffffff81168114610330575f80fd5b9250602084013567ffffffffffffffff8082111561034c575f80fd5b818601915086601f83011261035f575f80fd5b81358181111561036d575f80fd5b87602082850101111561037e575f80fd5b6020830194508093505050509250925092565b60208152816020820152818360408301375f818301604090810191909152601f9092017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0160101919050565b5f602082840312156103ed575f80fd5b505191905056";

    /// @notice Pre-flight (pin bare, Zoltu present), Zoltu-deploy the frozen
    /// creation code, assert it landed at the pin with the pinned codehash.
    function run() external {
        address pinned = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        if (pinned.code.length != 0) revert CloneFactoryAlreadyDeployed(pinned);
        if (LibRainDeploy.ZOLTU_FACTORY.code.length == 0) revert ZoltuFactoryMissing(LibRainDeploy.ZOLTU_FACTORY);

        console2.log("Deploying the rain-factory 0.1.1 CloneFactory on chain id", block.chainid);
        console2.log("at:", pinned);

        vm.startBroadcast();
        address deployed = LibRainDeploy.deployZoltu(CLONE_FACTORY_0_1_1_CREATION_CODE);
        vm.stopBroadcast();

        if (deployed != pinned) revert CloneFactoryLandedElsewhere(pinned, deployed);
        bytes32 codehash = deployed.codehash;
        if (codehash != LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH) {
            revert CloneFactoryCodehashMismatch(LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH, codehash);
        }

        console2.log("CloneFactory deployed at the pin with the pinned codehash.");
    }
}
