// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {
    IStoxScript,
    MigrationPrerequisite,
    MigrationWriter,
    ScriptDeclaration
} from "../../../../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../../../../src/lib/LibStoxMigrations.sol";

/// @dev The second timelock-written record, also waiting on the Safe line.
contract CTimelockLineSecondFixture is IStoxScript {
    function declaration() external pure returns (ScriptDeclaration memory declared) {
        declared = LibStoxMigrations.safeMigrationOnto(keccak256("fixture.timelock"), "t2", "t1", false);
        declared.writer = MigrationWriter.Timelock;
        MigrationPrerequisite[] memory prerequisites = new MigrationPrerequisite[](2);
        prerequisites[0] = MigrationPrerequisite({
            writer: MigrationWriter.Timelock, namespace: keccak256("fixture.timelock"), migration: "t1"
        });
        prerequisites[1] = MigrationPrerequisite({
            writer: MigrationWriter.Safe, namespace: keccak256("fixture.safe"), migration: "s1"
        });
        declared.prerequisites = prerequisites;
    }
}
