// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";

import {
    MigrationPrerequisite,
    MigrationWriter,
    ScriptDeclaration,
    ScriptKind
} from "../../../src/interface/IStoxScript.sol";
import {
    DeclarationCountMismatch,
    DuplicateRecord,
    IdNotScriptPath,
    LibScriptDeclarations,
    MigrationWithoutPrerequisite,
    MigrationWithoutRecord,
    RecordOnNonMigration,
    UnknownPrerequisite
} from "../../../src/lib/LibScriptDeclarations.sol";
import {LibStoxMigrations} from "../../../src/lib/LibStoxMigrations.sol";

contract LibScriptDeclarationsTest is Test {
    bytes32 internal constant OTHER_NAMESPACE = keccak256("other");

    function validate(string[] memory paths, ScriptDeclaration[] memory declarations) external pure {
        LibScriptDeclarations.validate(paths, declarations);
    }

    function one(string memory path, ScriptDeclaration memory d)
        internal
        pure
        returns (string[] memory paths, ScriptDeclaration[] memory declarations)
    {
        paths = new string[](1);
        paths[0] = path;
        declarations = new ScriptDeclaration[](1);
        declarations[0] = d;
    }

    function two(string memory a, ScriptDeclaration memory da, string memory b, ScriptDeclaration memory db)
        internal
        pure
        returns (string[] memory paths, ScriptDeclaration[] memory declarations)
    {
        paths = new string[](2);
        paths[0] = a;
        paths[1] = b;
        declarations = new ScriptDeclaration[](2);
        declarations[0] = da;
        declarations[1] = db;
    }

    function deployOnto(string memory path, bytes32 head) internal pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.safeMigrationOnto(LibStoxMigrations.NAMESPACE, keccak256(bytes(path)), head, false);
    }

    function testAValidLineOfScriptsPasses() external view {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two(
            "script/a.s.sol",
            deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            deployOnto("script/b.s.sol", keccak256("script/a.s.sol"))
        );
        this.validate(paths, declarations);
    }

    function testANonMigrationWithNoRecordPasses() external view {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            one("script/d.s.sol", LibStoxMigrations.notAMigration(ScriptKind.Deployment));
        this.validate(paths, declarations);
    }

    function testAMigrationWithNoIdIsInNoLine() external {
        ScriptDeclaration memory d = deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS);
        d.id = 0;
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one("script/a.s.sol", d);
        vm.expectRevert(abi.encodeWithSelector(MigrationWithoutRecord.selector, "script/a.s.sol"));
        this.validate(paths, declarations);
    }

    function testAMigrationWithNoNamespaceIsInNoLine() external {
        ScriptDeclaration memory d = deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS);
        d.namespace = 0;
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one("script/a.s.sol", d);
        vm.expectRevert(abi.encodeWithSelector(MigrationWithoutRecord.selector, "script/a.s.sol"));
        this.validate(paths, declarations);
    }

    function testAMigrationRecordedAfterNothingIsInNoLine() external {
        ScriptDeclaration memory d = deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS);
        d.prerequisites = new MigrationPrerequisite[](0);
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one("script/a.s.sol", d);
        vm.expectRevert(abi.encodeWithSelector(MigrationWithoutPrerequisite.selector, "script/a.s.sol"));
        this.validate(paths, declarations);
    }

    function testANonMigrationCarriesNoPartOfARecord() external {
        ScriptDeclaration[4] memory cases;
        for (uint256 c = 0; c < cases.length; c++) {
            cases[c] = LibStoxMigrations.notAMigration(ScriptKind.TimelockRehearsal);
        }
        cases[0].namespace = LibStoxMigrations.NAMESPACE;
        cases[1].id = keccak256("script/r.s.sol");
        cases[2].prerequisites = deployOnto("script/r.s.sol", MIGRATION_HEAD_GENESIS).prerequisites;
        cases[3].history = true;
        for (uint256 c = 0; c < cases.length; c++) {
            (string[] memory paths, ScriptDeclaration[] memory declarations) = one("script/r.s.sol", cases[c]);
            vm.expectRevert(abi.encodeWithSelector(RecordOnNonMigration.selector, "script/r.s.sol"));
            this.validate(paths, declarations);
        }
    }

    function testARecordInThisNamespaceIsKeyedByItsScriptPath() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            one("script/a.s.sol", deployOnto("script/other.s.sol", MIGRATION_HEAD_GENESIS));
        vm.expectRevert(abi.encodeWithSelector(IdNotScriptPath.selector, "script/a.s.sol"));
        this.validate(paths, declarations);
    }

    function testARecordInAnotherNamespaceIsKeyedFreely() external view {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one(
            "script/a.s.sol",
            LibStoxMigrations.safeMigrationOnto(OTHER_NAMESPACE, keccak256("x"), MIGRATION_HEAD_GENESIS, false)
        );
        this.validate(paths, declarations);
    }

    function testTwoScriptsCannotDeclareOneRecord() external {
        ScriptDeclaration memory d =
            LibStoxMigrations.safeMigrationOnto(OTHER_NAMESPACE, keccak256("x"), MIGRATION_HEAD_GENESIS, false);
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two("script/a.s.sol", d, "script/b.s.sol", d);
        vm.expectRevert(abi.encodeWithSelector(DuplicateRecord.selector, "script/b.s.sol", "script/a.s.sol"));
        this.validate(paths, declarations);
    }

    function testAPrerequisiteNoScriptDeclaresIsUnknown() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            one("script/b.s.sol", deployOnto("script/b.s.sol", keccak256("script/a.s.sol")));
        vm.expectRevert(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/b.s.sol", 0));
        this.validate(paths, declarations);
    }

    function testAPrerequisiteUnderAnotherWriterIsUnknown() external {
        ScriptDeclaration memory b = deployOnto("script/b.s.sol", keccak256("script/a.s.sol"));
        b.prerequisites[0].writer = MigrationWriter.Timelock;
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            two("script/a.s.sol", deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS), "script/b.s.sol", b);
        vm.expectRevert(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/b.s.sol", 0));
        this.validate(paths, declarations);
    }

    function testAPrerequisiteInAnotherNamespaceIsUnknown() external {
        ScriptDeclaration memory b = deployOnto("script/b.s.sol", keccak256("script/a.s.sol"));
        b.prerequisites[0].namespace = OTHER_NAMESPACE;
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            two("script/a.s.sol", deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS), "script/b.s.sol", b);
        vm.expectRevert(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/b.s.sol", 0));
        this.validate(paths, declarations);
    }

    function testAPrerequisiteOnANonMigrationIsUnknown() external {
        ScriptDeclaration memory a = LibStoxMigrations.notAMigration(ScriptKind.Deployment);
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            two("script/a.s.sol", a, "script/b.s.sol", deployOnto("script/b.s.sol", keccak256("script/a.s.sol")));
        vm.expectRevert(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/b.s.sol", 0));
        this.validate(paths, declarations);
    }

    function testAMigrationIsNotItsOwnPrerequisite() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            one("script/a.s.sol", deployOnto("script/a.s.sol", keccak256("script/a.s.sol")));
        vm.expectRevert(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/a.s.sol", 0));
        this.validate(paths, declarations);
    }

    function testAGenesisPrerequisiteWithNoNamespaceIsUnknown() external {
        ScriptDeclaration memory d = deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS);
        d.prerequisites[0].namespace = 0;
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one("script/a.s.sol", d);
        vm.expectRevert(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/a.s.sol", 0));
        this.validate(paths, declarations);
    }

    function testEveryDeclarationHasAPath() external {
        (, ScriptDeclaration[] memory declarations) =
            one("script/a.s.sol", deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS));
        vm.expectRevert(abi.encodeWithSelector(DeclarationCountMismatch.selector));
        this.validate(new string[](0), declarations);
    }
}
