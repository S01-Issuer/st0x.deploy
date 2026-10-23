// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    IMigrationRegistryV3,
    MIGRATION_HEAD_GENESIS,
    Prerequisite
} from "rain-deploy-0.1.22/src/interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.22/src/lib/LibMigrationRegistryDeploy.sol";
import {
    RUNTIME_CODE as MIGRATION_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.22/src/generated/0_1_21/MigrationRegistry.sol";

import {LibStoxMigrations} from "../../../src/lib/LibStoxMigrations.sol";

/// @title LibStoxMigrationsTest
/// @notice The migration ids name their scripts, every record is in the root
/// authority's line in this repo's namespace, and a delegate it approves
/// writes there.
contract LibStoxMigrationsTest is Test {
    /// @notice The st0x.deploy records live at this registry instance. A
    /// rain-deploy bump that moves it reads an empty line, so it must fail
    /// here, with a reason, before it reaches the role invariants.
    function testRegistryInstancePinned() external pure {
        assertEq(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            0x5A48e719785E11c4643EA4056D0861A6a69e91a0,
            "st0x.deploy migration records live at this registry instance"
        );
        assertEq(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
            0xa78caf9b315d637f5bdc94b2168007bc64d7b172844deaf6e0dcabf418ee5c56,
            "st0x.deploy migration records live at this registry instance"
        );
    }

    function testNamespace() external pure {
        assertEq(LibStoxMigrations.NAMESPACE, keccak256("st0x.deploy"));
    }

    /// @notice The writer is the root authority.
    function testWriterIsTheRootAuthority() external pure {
        assertEq(LibStoxMigrations.WRITER, 0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c);
    }

    function testIdsNameTheirScripts() external pure {
        assertEq(
            LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
            keccak256("script/20261006-orchestrator-admin-to-timelock.s.sol")
        );
    }

    /// @notice The registry call writes the root authority's line in this
    /// repo's namespace, at the pinned registry.
    function testApplyMigrationCallWritesTheRootLine() external {
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, MIGRATION_REGISTRY_RUNTIME_CODE);
        Prerequisite[] memory prerequisites = LibStoxMigrations.onto(MIGRATION_HEAD_GENESIS);

        (address to, bytes memory data) =
            LibStoxMigrations.applyMigrationCall(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK, prerequisites);

        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(
            data,
            abi.encodeCall(
                IMigrationRegistryV3.applyMigrationV3,
                (
                    LibStoxMigrations.WRITER,
                    LibStoxMigrations.NAMESPACE,
                    LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
                    prerequisites
                )
            )
        );
    }

    /// @notice A delegate the root authority approves writes the line, and
    /// `approved`, `applied` and `head` read it back; one it has not approved
    /// is refused.
    function testApprovedDelegateWritesTheRootLine() external {
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, MIGRATION_REGISTRY_RUNTIME_CODE);
        IMigrationRegistryV3 registry =
            IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        address safe = makeAddr("safe");
        address stranger = makeAddr("stranger");
        (address to, bytes memory data) = LibStoxMigrations.applyMigrationCall(
            LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK, LibStoxMigrations.onto(MIGRATION_HEAD_GENESIS)
        );

        assertFalse(LibStoxMigrations.approved(safe));
        vm.prank(stranger);
        (bool strangerOk,) = to.call(data);
        assertFalse(strangerOk, "an unapproved caller cannot write the line");

        vm.prank(LibStoxMigrations.WRITER);
        registry.approveV3(LibStoxMigrations.NAMESPACE, safe);
        assertTrue(LibStoxMigrations.approved(safe));
        assertFalse(LibStoxMigrations.approved(stranger));

        assertEq(LibStoxMigrations.head(), MIGRATION_HEAD_GENESIS);
        vm.prank(safe);
        (bool ok,) = to.call(data);
        assertTrue(ok, "the approved Safe writes the line");
        assertEq(LibStoxMigrations.applied(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK), block.timestamp);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
    }
}
