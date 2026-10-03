// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.16.2/src/Vm.sol";

import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.11/src/lib/LibMigrationRegistryDeploy.sol";
import {
    RUNTIME_CODE as MIGRATION_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.11/src/generated/candidate/MigrationRegistry.sol";

/// @title LibTestMigrationRegistry
/// @notice Puts the real `MigrationRegistry` at its real address on a local
/// test EVM, so a contract that records its own migrations can be deployed and
/// migrated in a unit test.
///
/// Etched rather than mocked, for the same reason as the address registry:
/// every `LibMigrationRegistry` entry point verifies the code hash at the
/// pinned address first, and the pinned hash is the hash of the recorded
/// runtime code, so only that code at that address satisfies it.
///
/// There is no bind helper and no seed helper. A record is keyed by
/// `msg.sender`, so the only account that can write a contract's line is that
/// contract, and a test that wants a line to hold something makes the contract
/// put it there. Reaching into the registry's storage to fake a record would
/// be faking the one thing these tests are about.
library LibTestMigrationRegistry {
    /// @notice Etch the registry's runtime code at its pinned address, with
    /// every line empty. A read of any migration then answers zero and a
    /// first write is accepted against `MIGRATION_HEAD_GENESIS`.
    /// @param vm The forge VM.
    function etch(Vm vm) internal {
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, MIGRATION_REGISTRY_RUNTIME_CODE);
    }

    /// @notice Remove the registry's code, so a read or a write reverts
    /// `UnexpectedMigrationRegistryCodeHash` rather than answering.
    /// @param vm The forge VM.
    function unEtch(Vm vm) internal {
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, hex"");
    }
}
