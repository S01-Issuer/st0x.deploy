// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    IMigrationRegistryV3,
    MIGRATION_HEAD_GENESIS
} from "rain-deploy-0.1.22/src/interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.22/src/lib/LibMigrationRegistry.sol";
import {IRegistryDelegatesV1} from "rain-deploy-0.1.22/src/interface/IRegistryDelegatesV1.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.22/src/lib/LibMigrationRegistryDeploy.sol";
import {
    RUNTIME_CODE as MIGRATION_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.22/src/generated/candidate/MigrationRegistry.sol";

import {ScriptDeclaration} from "../../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../../src/lib/LibStoxMigrations.sol";

/// @title LibStoxMigrationsTest
/// @notice Every record is in the root authority's line in this repo's
/// namespace, and a delegate it approves writes there.
contract LibStoxMigrationsTest is Test {
    /// @notice The st0x.deploy records live at this registry instance. A
    /// rain-deploy bump that moves it strands every record already written,
    /// so it must fail here, with a reason, before it reaches the role
    /// invariants.
    function testRegistryInstancePinned() external pure {
        assertEq(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            0x5A48e719785E11c4643EA4056D0861A6a69e91a0,
            "st0x.deploy migration records live at this registry instance; moving it strands them"
        );
        assertEq(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
            0xa78caf9b315d637f5bdc94b2168007bc64d7b172844deaf6e0dcabf418ee5c56,
            "st0x.deploy migration records live at this registry instance; moving it strands them"
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

    function etchRegistry() internal {
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, MIGRATION_REGISTRY_RUNTIME_CODE);
    }

    function adminMove() internal pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.migrationOnto(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK, MIGRATION_HEAD_GENESIS);
    }

    /// @notice The record call writes the declared id onto the declared head
    /// in the root authority's line, at the pinned registry.
    function testRecordCallWritesTheRootLine() external {
        etchRegistry();
        bytes32 headMigration = keccak256("head");

        (address to, bytes memory data) = LibStoxMigrations.recordCall(
            LibStoxMigrations.migrationOnto(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK, headMigration)
        );

        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(
            data,
            abi.encodeCall(
                IMigrationRegistryV3.applyMigrationV3,
                (
                    LibStoxMigrations.WRITER,
                    LibStoxMigrations.NAMESPACE,
                    LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
                    LibStoxMigrations.onto(headMigration)
                )
            )
        );
        assertEq(LibStoxMigrations.onto(headMigration).length, 1);
        assertEq(LibStoxMigrations.onto(headMigration)[0].writer, LibStoxMigrations.WRITER);
        assertEq(LibStoxMigrations.onto(headMigration)[0].namespace, LibStoxMigrations.NAMESPACE);
        assertEq(LibStoxMigrations.onto(headMigration)[0].migration, headMigration);
    }

    /// @notice The record call refuses a registry whose code is not the
    /// pinned one.
    function testRecordCallChecksTheRegistryCode() external {
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(hex"00")
            )
        );
        this.externalRecordCall();
    }

    function externalRecordCall() external view returns (address, bytes memory) {
        return LibStoxMigrations.recordCall(adminMove());
    }

    /// @notice A delegate the root authority approves writes the root line,
    /// and `approved`, `applied` and `head` read it back.
    function testApprovedDelegateLandsInTheRootLine() external {
        etchRegistry();
        vm.warp(1_800_000_000);
        address safe = makeAddr("safe");
        assertFalse(LibStoxMigrations.approved(safe));

        vm.prank(LibStoxMigrations.WRITER);
        IRegistryDelegatesV1(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .approveV3(LibStoxMigrations.NAMESPACE, safe);
        assertTrue(LibStoxMigrations.approved(safe));
        assertFalse(LibStoxMigrations.approved(makeAddr("other")));

        assertEq(LibStoxMigrations.head(), MIGRATION_HEAD_GENESIS);
        (address to, bytes memory data) = LibStoxMigrations.recordCall(adminMove());
        vm.prank(safe);
        (bool ok,) = to.call(data);
        assertTrue(ok, "the approved Safe writes the root line");

        assertEq(LibStoxMigrations.applied(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK), 1_800_000_000);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
    }

    /// @notice An account the root authority never approved cannot write the
    /// root line.
    function testUnapprovedAccountIsRefused() external {
        etchRegistry();
        address other = makeAddr("other");
        (address to, bytes memory data) = LibStoxMigrations.recordCall(adminMove());

        vm.prank(other);
        (bool ok, bytes memory reason) = to.call(data);
        assertFalse(ok, "sent by an unapproved account");
        assertEq(
            reason,
            abi.encodeWithSelector(
                IRegistryDelegatesV1.NotApproved.selector, LibStoxMigrations.WRITER, LibStoxMigrations.NAMESPACE, other
            )
        );
        assertEq(LibStoxMigrations.head(), MIGRATION_HEAD_GENESIS);
    }
}
