// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.10/src/lib/LibRainDeploy.sol";
import {LibAddressRegistryDeploy} from "rain-deploy-0.1.10/src/lib/LibAddressRegistryDeploy.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.10/src/lib/LibMigrationRegistryDeploy.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";

/// @title OrchestratorRegistryPrerequisitesTest
/// @notice `ST0xOrchestrator` reads `rain-deploy`'s two registries on chain:
/// `initialize` resolves the token-owner Safe through `AddressRegistry`, and
/// both `initialize` and `migrate` record into `MigrationRegistry`. Every one
/// of those entry points calls the library's `checkCodeHash` first, which
/// reverts unless the pinned address holds the pinned code — and an address
/// with NO code hits it too, because an empty account's code hash is zero and
/// never the expected value.
///
/// So an orchestrator on a chain whose registries are absent cannot be
/// initialized and cannot be migrated. That failure surfaces as a reverted
/// transaction against a live proxy, which is the worst place to find it, and
/// nothing else in this repo pins the dependency even though it pins every
/// other on-chain prerequisite. This is that pin.
///
/// @dev The assertion is an implication — orchestrator present on a chain
/// implies both registries pinned there — rather than an unconditional
/// per-chain check, because the registries legitimately do not exist on every
/// network this repo targets, and demanding them on a chain with no
/// orchestrator would assert an operator obligation nobody has taken on.
/// `testSomeNetworkCarriesTheOrchestrator` is what stops the implication
/// passing vacuously: an implication whose antecedent is false everywhere
/// asserts nothing at all, so if the orchestrator pin were ever changed to an
/// address that exists on no network, this suite would go quietly green
/// without that second test.
///
/// Unpinned head forks, because the question is whether the registries are
/// there NOW. A pinned block would answer for the block it pinned.
contract OrchestratorRegistryPrerequisitesTest is Test {
    /// Thrown when a chain carries the orchestrator but not the registry the
    /// orchestrator reads.
    /// @param network The `foundry.toml` rpc alias of the offending chain.
    /// @param registry The registry address that failed its code hash.
    /// @param expectedCodeHash The code hash the orchestrator was compiled
    /// against.
    /// @param actualCodeHash The code hash actually found, zero for an empty
    /// account.
    error RegistryMissingOnOrchestratorNetwork(
        string network, address registry, bytes32 expectedCodeHash, bytes32 actualCodeHash
    );

    /// Every chain that carries the orchestrator instance MUST carry both
    /// registries at their pinned addresses with their pinned code hashes,
    /// because the orchestrator's `initialize` and `migrate` both revert
    /// otherwise.
    function testOrchestratorNetworksCarryBothRegistries() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        // Every fork is created before any is selected. Creating a fork while
        // another is selected leaves the later networks reading the default
        // EVM, where every address is an empty account — which here would read
        // as "no orchestrator" and pass vacuously on all but the first chain.
        uint256[] memory forks = LibRainDeploy.createForks(vm, networks);

        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forks[i]);

            if (LibProdDeployV4.ST0X_ORCHESTRATOR_INSTANCE.codehash == bytes32(0)) {
                continue;
            }

            bytes32 addressRegistryCodeHash = LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.codehash;
            if (addressRegistryCodeHash != LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH) {
                revert RegistryMissingOnOrchestratorNetwork(
                    networks[i],
                    LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
                    LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
                    addressRegistryCodeHash
                );
            }

            bytes32 migrationRegistryCodeHash = LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.codehash;
            if (migrationRegistryCodeHash != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH) {
                revert RegistryMissingOnOrchestratorNetwork(
                    networks[i],
                    LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
                    LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                    migrationRegistryCodeHash
                );
            }
        }
    }

    /// At least one deployment network MUST carry the orchestrator instance.
    ///
    /// This is the non-vacuity guard for
    /// `testOrchestratorNetworksCarryBothRegistries`, not a statement about
    /// how many chains the orchestrator belongs on. It fails if the
    /// orchestrator pin is moved to an address that is live nowhere, which is
    /// the one way the registry implication above can pass while checking
    /// nothing.
    function testSomeNetworkCarriesTheOrchestrator() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        uint256[] memory forks = LibRainDeploy.createForks(vm, networks);

        uint256 found = 0;
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forks[i]);
            if (LibProdDeployV4.ST0X_ORCHESTRATOR_INSTANCE.codehash != bytes32(0)) {
                found++;
            }
        }

        assertGt(found, 0, "orchestrator instance is live on no deployment network");
    }
}
