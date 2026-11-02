// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {IMigrationRegistryV5, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.29/src/interface/IMigrationRegistryV5.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.29/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.29/src/lib/LibMigrationRegistryDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.29/src/lib/LibSafeTx.sol";
import {
    RUNTIME_CODE as MIGRATION_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.29/src/generated/candidate/MigrationRegistry.sol";

import {GrantEuAuthoriserRoles} from "../../script/20261006-grant-eu-authoriser-roles.s.sol";
import {LibRbacMigration} from "../../src/lib/LibRbacMigration.sol";

/// @title GrantEuAuthoriserRolesTest
/// @notice The bundle's first call records the grant in the Safe's RBAC line.
contract GrantEuAuthoriserRolesTest is Test {
    function recordTx(address safe) internal returns (SafeTx memory) {
        return new GrantEuAuthoriserRoles().grantBundle(makeAddr("clone"), safe, makeAddr("timelock"))[0];
    }

    function testBundleOpensWithTheSafesRbacRecordOntoGenesis() external {
        address safe = makeAddr("safe");
        SafeTx memory record = recordTx(safe);

        assertEq(record.to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(record.value, 0);
        assertEq(uint8(record.operation), uint8(Enum.Operation.Call));
        assertEq(
            record.data,
            abi.encodeCall(
                IMigrationRegistryV5.applyMigrationV5,
                (
                    safe,
                    LibRbacMigration.STOX_RBAC_NAMESPACE,
                    LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER,
                    LibMigrationRegistry.onto(safe, LibRbacMigration.STOX_RBAC_NAMESPACE, MIGRATION_HEAD_GENESIS),
                    ""
                )
            )
        );
    }

    function testBundleRecordSentByTheSafeLandsInItsRbacLine() external {
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, MIGRATION_REGISTRY_RUNTIME_CODE);
        vm.warp(1_800_000_000);
        address safe = makeAddr("safe");
        SafeTx memory record = recordTx(safe);

        vm.prank(safe);
        (bool ok,) = record.to.call(record.data);
        assertTrue(ok);

        assertEq(
            LibMigrationRegistry.appliedV5(
                safe, LibRbacMigration.STOX_RBAC_NAMESPACE, LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER
            ),
            1_800_000_000
        );
        assertEq(
            LibMigrationRegistry.headV5(safe, LibRbacMigration.STOX_RBAC_NAMESPACE),
            LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER
        );
    }
}
