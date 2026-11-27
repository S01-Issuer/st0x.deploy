// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IMigrationRegistryV5, Prerequisite} from "rain-deploy-0.1.43/src/interface/IMigrationRegistryV5.sol";
import {IRegistryDelegatesV3} from "rain-deploy-0.1.43/src/interface/IRegistryDelegatesV3.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.43/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.43/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.43/src/lib/LibRegistryAuthority.sol";
import {
    RUNTIME_CODE as MIGRATION_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.43/src/generated/candidate/MigrationRegistry.sol";

import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

/// @title LibTestRootLine
/// @notice A local `MigrationRegistry` and writes on the root line
/// (`LibRegistryAuthority.ROOT_AUTHORITY`, `LibStoxMigrations.NAMESPACE`).
library LibTestRootLine {
    function etchRegistry(Vm vm) internal {
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, MIGRATION_REGISTRY_RUNTIME_CODE);
    }

    function approve(Vm vm, address delegate) internal {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        IRegistryDelegatesV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS).approveUnscopedV5(delegate);
    }

    function approveScope(Vm vm, bytes32 scope, address delegate) internal {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        IRegistryDelegatesV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS).approveV5(scope, delegate);
    }

    function revokeScope(Vm vm, bytes32 scope, address delegate) internal {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        IRegistryDelegatesV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS).revokeV5(scope, delegate);
    }

    function revokeUnscoped(Vm vm, address delegate) internal {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        IRegistryDelegatesV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS).revokeUnscopedV5(delegate);
    }

    /// @dev The `applyMigrationV5` calldata that records `id` onto `onto` on the root line.
    function recordCalldata(bytes32 id, bytes32 onto) internal pure returns (bytes memory) {
        Prerequisite[] memory prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({
            writer: LibRegistryAuthority.ROOT_AUTHORITY, namespace: LibStoxMigrations.NAMESPACE, migration: onto
        });
        return abi.encodeCall(
            IMigrationRegistryV5.applyMigrationV5,
            (LibRegistryAuthority.ROOT_AUTHORITY, LibStoxMigrations.NAMESPACE, id, prerequisites, "")
        );
    }

    /// @notice Revokes both approvals that let `delegate` write the root line.
    function revoke(Vm vm, address delegate) internal {
        revokeUnscoped(vm, delegate);
        revokeScope(vm, LibStoxMigrations.NAMESPACE, delegate);
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
