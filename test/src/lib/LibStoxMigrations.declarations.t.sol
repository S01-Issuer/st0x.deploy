// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Prerequisite} from "rain-deploy-0.1.29/src/interface/IMigrationRegistryV3.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";

import {MigrationPrerequisite, MigrationWriter, ScriptDeclaration} from "../../../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";

/// @title LibStoxMigrationsDeclarationsTest
/// @notice The declaration helpers resolve roles to each chain's Safe and
/// timelock.
contract LibStoxMigrationsDeclarationsTest is Test {
    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function testSafeMigrationOntoIsOneSafePrerequisiteInItsOwnNamespace() external pure {
        ScriptDeclaration memory declared = LibStoxMigrations.safeMigrationOnto("ns", "id", "head", true);
        assertTrue(declared.migration);
        assertEq(declared.namespace, "ns");
        assertEq(declared.id, "id");
        assertEq(uint256(declared.writer), uint256(MigrationWriter.Safe));
        assertTrue(declared.history);
        assertEq(declared.prerequisites.length, 1);
        assertEq(uint256(declared.prerequisites[0].writer), uint256(MigrationWriter.Safe));
        assertEq(declared.prerequisites[0].namespace, "ns");
        assertEq(declared.prerequisites[0].migration, "head");
        assertFalse(LibStoxMigrations.safeMigrationOnto("ns", "id", "head", false).history);
    }

    function testNotAMigrationCarriesNoRecord() external pure {
        ScriptDeclaration memory declared = LibStoxMigrations.notAMigration();
        assertFalse(declared.migration);
        assertEq(declared.namespace, 0);
        assertEq(declared.id, 0);
        assertEq(declared.prerequisites.length, 0);
        assertFalse(declared.history);
    }

    function testWriterForChainIdIsTheChainsSafeOrTimelock() external pure {
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            uint256 chainId = nets[i].chainId;
            assertEq(
                LibStoxMigrations.writerForChainId(MigrationWriter.Safe, chainId),
                LibSafeInvariants.safeForChainId(chainId)
            );
            assertEq(
                LibStoxMigrations.writerForChainId(MigrationWriter.Timelock, chainId),
                LibTimelockInvariants.timelockForChainId(chainId)
            );
        }
    }

    function testPrerequisitesResolveEachWriter() external pure {
        MigrationPrerequisite[] memory declared = new MigrationPrerequisite[](2);
        declared[0] = MigrationPrerequisite({writer: MigrationWriter.Timelock, namespace: "a", migration: "b"});
        declared[1] = MigrationPrerequisite({writer: MigrationWriter.Safe, namespace: "c", migration: "d"});
        ScriptDeclaration memory migration = LibStoxMigrations.safeMigrationOnto("a", "e", "b", false);
        migration.prerequisites = declared;
        Prerequisite[] memory resolved = LibStoxMigrations.prerequisitesFor(migration, address(1), address(2));
        assertEq(resolved.length, 2);
        assertEq(resolved[0].writer, address(2));
        assertEq(resolved[0].namespace, "a");
        assertEq(resolved[0].migration, "b");
        assertEq(resolved[1].writer, address(1));
        assertEq(resolved[1].namespace, "c");
        assertEq(resolved[1].migration, "d");
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            resolved = LibStoxMigrations.prerequisitesForChainId(migration, nets[i].chainId);
            assertEq(resolved[0].writer, LibTimelockInvariants.timelockForChainId(nets[i].chainId));
            assertEq(resolved[1].writer, LibSafeInvariants.safeForChainId(nets[i].chainId));
        }
    }
}
