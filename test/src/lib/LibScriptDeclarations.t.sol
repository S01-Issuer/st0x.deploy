// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";

import {MigrationPrerequisite, MigrationWriter, ScriptDeclaration} from "../../../src/interface/IStoxScript.sol";
import {
    DeclarationCountMismatch,
    DuplicateRecord,
    ForkedLine,
    IdNotScriptPath,
    LibScriptDeclarations,
    MigrationWithoutPrerequisite,
    MigrationWithoutRecord,
    NotOntoOwnLine,
    OwnLinePrerequisite,
    RecordOnNonMigration,
    UnknownPrerequisite,
    UnrootedLine
} from "../../../src/lib/LibScriptDeclarations.sol";
import {LibStoxMigrations} from "../../../src/lib/LibStoxMigrations.sol";

contract LibScriptDeclarationsTest is Test {
    bytes32 internal constant OTHER_NAMESPACE = keccak256("other");

    function validate(string[] memory paths, ScriptDeclaration[] memory declarations) external pure {
        LibScriptDeclarations.validate(paths, declarations);
    }

    function one(string memory path, ScriptDeclaration memory declared)
        internal
        pure
        returns (string[] memory paths, ScriptDeclaration[] memory declarations)
    {
        paths = new string[](1);
        paths[0] = path;
        declarations = new ScriptDeclaration[](1);
        declarations[0] = declared;
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
            one("script/declared.s.sol", LibStoxMigrations.notAMigration());
        this.validate(paths, declarations);
    }

    function testAMigrationWithNoIdIsInNoLine() external {
        ScriptDeclaration memory declared = deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS);
        declared.id = 0;
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one("script/a.s.sol", declared);
        vm.expectRevert(abi.encodeWithSelector(MigrationWithoutRecord.selector, "script/a.s.sol"));
        this.validate(paths, declarations);
    }

    function testAMigrationWithNoNamespaceIsInNoLine() external {
        ScriptDeclaration memory declared = deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS);
        declared.namespace = 0;
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one("script/a.s.sol", declared);
        vm.expectRevert(abi.encodeWithSelector(MigrationWithoutRecord.selector, "script/a.s.sol"));
        this.validate(paths, declarations);
    }

    function testAMigrationRecordedAfterNothingIsInNoLine() external {
        ScriptDeclaration memory declared = deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS);
        declared.prerequisites = new MigrationPrerequisite[](0);
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one("script/a.s.sol", declared);
        vm.expectRevert(abi.encodeWithSelector(MigrationWithoutPrerequisite.selector, "script/a.s.sol"));
        this.validate(paths, declarations);
    }

    function testANonMigrationCarriesNoPartOfARecord() external {
        ScriptDeclaration[4] memory cases;
        for (uint256 c = 0; c < cases.length; c++) {
            cases[c] = LibStoxMigrations.notAMigration();
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
        ScriptDeclaration memory declared =
            LibStoxMigrations.safeMigrationOnto(OTHER_NAMESPACE, keccak256("x"), MIGRATION_HEAD_GENESIS, false);
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            two("script/a.s.sol", declared, "script/b.s.sol", declared);
        vm.expectRevert(abi.encodeWithSelector(DuplicateRecord.selector, "script/b.s.sol", "script/a.s.sol"));
        this.validate(paths, declarations);
    }

    function testAPrerequisiteNoScriptDeclaresIsUnknown() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            one("script/b.s.sol", deployOnto("script/b.s.sol", keccak256("script/a.s.sol")));
        vm.expectRevert(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/b.s.sol", 0));
        this.validate(paths, declarations);
    }

    function three(
        string memory a,
        ScriptDeclaration memory declaredA,
        string memory b,
        ScriptDeclaration memory declaredB,
        string memory c,
        ScriptDeclaration memory declaredC
    ) internal pure returns (string[] memory paths, ScriptDeclaration[] memory declarations) {
        paths = new string[](3);
        paths[0] = a;
        paths[1] = b;
        paths[2] = c;
        declarations = new ScriptDeclaration[](3);
        declarations[0] = declaredA;
        declarations[1] = declaredB;
        declarations[2] = declaredC;
    }

    function otherLine(bytes32 id, bytes32 head) internal pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.safeMigrationOnto(OTHER_NAMESPACE, id, head, false);
    }

    function withSecond(ScriptDeclaration memory declared, MigrationPrerequisite memory second)
        internal
        pure
        returns (ScriptDeclaration memory)
    {
        MigrationPrerequisite[] memory prerequisites = new MigrationPrerequisite[](2);
        prerequisites[0] = declared.prerequisites[0];
        prerequisites[1] = second;
        declared.prerequisites = prerequisites;
        return declared;
    }

    function expectRevertOn(bytes memory reason, string[] memory paths, ScriptDeclaration[] memory declarations)
        internal
    {
        vm.expectRevert(reason);
        this.validate(paths, declarations);
    }

    function testASecondPrerequisiteInAnotherLinePasses() external view {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = three(
            "script/a.s.sol",
            deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS),
            "script/o.s.sol",
            otherLine("o", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            withSecond(
                deployOnto("script/b.s.sol", keccak256("script/a.s.sol")),
                MigrationPrerequisite({writer: MigrationWriter.Safe, namespace: OTHER_NAMESPACE, migration: "o"})
            )
        );
        this.validate(paths, declarations);
    }

    function testAFirstPrerequisiteUnderAnotherWriterIsNotOntoItsOwnLine() external {
        ScriptDeclaration memory declared = deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS);
        declared.prerequisites[0].writer = MigrationWriter.Timelock;
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one("script/a.s.sol", declared);
        expectRevertOn(abi.encodeWithSelector(NotOntoOwnLine.selector, "script/a.s.sol"), paths, declarations);
    }

    function testAFirstPrerequisiteInAnotherNamespaceIsNotOntoItsOwnLine() external {
        ScriptDeclaration memory declared = deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS);
        declared.prerequisites[0].namespace = OTHER_NAMESPACE;
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one("script/a.s.sol", declared);
        expectRevertOn(abi.encodeWithSelector(NotOntoOwnLine.selector, "script/a.s.sol"), paths, declarations);
    }

    function testALaterPrerequisiteInItsOwnLineIsRefused() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two(
            "script/a.s.sol",
            deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            withSecond(
                deployOnto("script/b.s.sol", keccak256("script/a.s.sol")),
                MigrationPrerequisite({
                    writer: MigrationWriter.Safe,
                    namespace: LibStoxMigrations.NAMESPACE,
                    migration: keccak256("script/a.s.sol")
                })
            )
        );
        expectRevertOn(abi.encodeWithSelector(OwnLinePrerequisite.selector, "script/b.s.sol", 1), paths, declarations);
    }

    function testALaterPrerequisiteUnderAnotherWriterIsUnknown() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = three(
            "script/a.s.sol",
            deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS),
            "script/o.s.sol",
            otherLine("o", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            withSecond(
                deployOnto("script/b.s.sol", keccak256("script/a.s.sol")),
                MigrationPrerequisite({writer: MigrationWriter.Timelock, namespace: OTHER_NAMESPACE, migration: "o"})
            )
        );
        expectRevertOn(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/b.s.sol", 1), paths, declarations);
    }

    function testALaterPrerequisiteNamingAnUndeclaredIdIsUnknown() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = three(
            "script/a.s.sol",
            deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS),
            "script/o.s.sol",
            otherLine("o", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            withSecond(
                deployOnto("script/b.s.sol", keccak256("script/a.s.sol")),
                MigrationPrerequisite({writer: MigrationWriter.Safe, namespace: OTHER_NAMESPACE, migration: "typo"})
            )
        );
        expectRevertOn(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/b.s.sol", 1), paths, declarations);
    }

    function testALaterPrerequisiteNamingGenesisIsUnknown() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two(
            "script/a.s.sol",
            deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            withSecond(
                deployOnto("script/b.s.sol", keccak256("script/a.s.sol")),
                MigrationPrerequisite({
                    writer: MigrationWriter.Safe, namespace: OTHER_NAMESPACE, migration: MIGRATION_HEAD_GENESIS
                })
            )
        );
        expectRevertOn(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/b.s.sol", 1), paths, declarations);
    }

    function testAHeadNamingAnUndeclaredIdBesideARealRecordIsUnknown() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two(
            "script/a.s.sol",
            deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            deployOnto("script/b.s.sol", keccak256("script/typo.s.sol"))
        );
        expectRevertOn(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/b.s.sol", 0), paths, declarations);
    }

    function testAHeadOnANonMigrationIsUnknown() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two(
            "script/a.s.sol",
            LibStoxMigrations.notAMigration(),
            "script/b.s.sol",
            deployOnto("script/b.s.sol", keccak256("script/a.s.sol"))
        );
        expectRevertOn(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/b.s.sol", 0), paths, declarations);
    }

    function testAMigrationIsNotItsOwnHead() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            one("script/a.s.sol", deployOnto("script/a.s.sol", keccak256("script/a.s.sol")));
        expectRevertOn(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/a.s.sol", 0), paths, declarations);
    }

    function testTheGenesisIdIsNoRecord() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            one("script/a.s.sol", otherLine(MIGRATION_HEAD_GENESIS, MIGRATION_HEAD_GENESIS));
        expectRevertOn(abi.encodeWithSelector(MigrationWithoutRecord.selector, "script/a.s.sol"), paths, declarations);
    }

    function testOneIdInTwoNamespacesIsTwoRecords() external view {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two(
            "script/a.s.sol",
            otherLine("x", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            LibStoxMigrations.safeMigrationOnto(keccak256("third"), "x", MIGRATION_HEAD_GENESIS, false)
        );
        this.validate(paths, declarations);
    }

    function testTwoMigrationsOntoOneHeadForkTheLine() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two(
            "script/a.s.sol",
            otherLine("x", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            otherLine("y", MIGRATION_HEAD_GENESIS)
        );
        expectRevertOn(
            abi.encodeWithSelector(ForkedLine.selector, "script/b.s.sol", "script/a.s.sol"), paths, declarations
        );
    }

    function testOneHeadInTwoLinesIsNoFork() external view {
        ScriptDeclaration memory timelockLine = otherLine("y", MIGRATION_HEAD_GENESIS);
        timelockLine.writer = MigrationWriter.Timelock;
        timelockLine.prerequisites[0].writer = MigrationWriter.Timelock;
        (string[] memory paths, ScriptDeclaration[] memory declarations) = three(
            "script/a.s.sol",
            otherLine("x", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            timelockLine,
            "script/c.s.sol",
            deployOnto("script/c.s.sol", MIGRATION_HEAD_GENESIS)
        );
        this.validate(paths, declarations);
    }

    function testACycleNeverReachesGenesis() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            two("script/a.s.sol", otherLine("x", "y"), "script/b.s.sol", otherLine("y", "x"));
        expectRevertOn(abi.encodeWithSelector(UnrootedLine.selector, "script/a.s.sol"), paths, declarations);
    }

    function testALineThroughAnUnknownHeadIsUnrooted() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            two("script/a.s.sol", otherLine("x", "y"), "script/b.s.sol", otherLine("y", "missing"));
        expectRevertOn(abi.encodeWithSelector(UnrootedLine.selector, "script/a.s.sol"), paths, declarations);
    }

    function testALaterPrerequisiteNamingAnIdFromAnotherNamespaceIsUnknown() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = three(
            "script/a.s.sol",
            deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS),
            "script/o.s.sol",
            otherLine("o", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            withSecond(
                deployOnto("script/b.s.sol", keccak256("script/a.s.sol")),
                MigrationPrerequisite({writer: MigrationWriter.Safe, namespace: keccak256("third"), migration: "o"})
            )
        );
        expectRevertOn(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/b.s.sol", 1), paths, declarations);
    }

    function testALaterPrerequisiteInTheSameNamespaceUnderAnotherWriterPasses() external view {
        ScriptDeclaration memory timelockFirst = otherLine("t1", MIGRATION_HEAD_GENESIS);
        timelockFirst.writer = MigrationWriter.Timelock;
        timelockFirst.prerequisites[0].writer = MigrationWriter.Timelock;
        ScriptDeclaration memory timelockSecond = withSecond(
            otherLine("t2", "t1"),
            MigrationPrerequisite({writer: MigrationWriter.Safe, namespace: OTHER_NAMESPACE, migration: "o"})
        );
        timelockSecond.writer = MigrationWriter.Timelock;
        timelockSecond.prerequisites[0].writer = MigrationWriter.Timelock;
        (string[] memory paths, ScriptDeclaration[] memory declarations) = three(
            "script/a.s.sol",
            otherLine("o", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            timelockFirst,
            "script/c.s.sol",
            timelockSecond
        );
        this.validate(paths, declarations);
    }

    function testALineThroughAnUnknownHeadAmongManyIsUnrooted() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = three(
            "script/a.s.sol",
            otherLine("x", "y"),
            "script/b.s.sol",
            otherLine("y", "missing"),
            "script/c.s.sol",
            deployOnto("script/c.s.sol", MIGRATION_HEAD_GENESIS)
        );
        expectRevertOn(abi.encodeWithSelector(UnrootedLine.selector, "script/a.s.sol"), paths, declarations);
    }

    function testALaterPrerequisiteWithNoNamespaceIsUnknownOnTheScriptThatNamesIt() external {
        ScriptDeclaration memory noNamespace = otherLine("z", MIGRATION_HEAD_GENESIS);
        noNamespace.namespace = 0;
        (string[] memory paths, ScriptDeclaration[] memory declarations) = three(
            "script/a.s.sol",
            deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            withSecond(
                deployOnto("script/b.s.sol", keccak256("script/a.s.sol")),
                MigrationPrerequisite({writer: MigrationWriter.Safe, namespace: 0, migration: "z"})
            ),
            "script/c.s.sol",
            noNamespace
        );
        expectRevertOn(abi.encodeWithSelector(UnknownPrerequisite.selector, "script/b.s.sol", 1), paths, declarations);
    }

    function testEveryDeclarationHasAPath() external {
        (, ScriptDeclaration[] memory declarations) =
            one("script/a.s.sol", deployOnto("script/a.s.sol", MIGRATION_HEAD_GENESIS));
        vm.expectRevert(abi.encodeWithSelector(DeclarationCountMismatch.selector));
        this.validate(new string[](0), declarations);
    }
}
