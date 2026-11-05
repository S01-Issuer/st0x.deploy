// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IMigrationRegistryV5} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {IRegistryDelegatesV3} from "rain-deploy-0.1.30/src/interface/IRegistryDelegatesV3.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {
    RUNTIME_CODE as MIGRATION_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.30/src/generated/candidate/MigrationRegistry.sol";

import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

/// @title LibTestRootLine
/// @notice A local `MigrationRegistry` and writes on the root line
/// (`ROOT_AUTHORITY`, `LibStoxMigrations.NAMESPACE`).
library LibTestRootLine {
    function etchRegistry(Vm vm) internal {
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, MIGRATION_REGISTRY_RUNTIME_CODE);
    }

    function approve(Vm vm, address delegate) internal {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        IRegistryDelegatesV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS).approveUnscopedV5(delegate);
    }

    function write(Vm vm, address safe, bytes32 id, bytes32 onto) internal {
        vm.prank(safe);
        IMigrationRegistryV5(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigrationV5(
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxMigrations.NAMESPACE,
                id,
                LibMigrationRegistry.onto(LibRegistryAuthority.ROOT_AUTHORITY, LibStoxMigrations.NAMESPACE, onto),
                ""
            );
    }
}
