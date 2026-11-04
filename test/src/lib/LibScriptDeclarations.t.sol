// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";

import {ScriptDeclaration} from "../../../src/interface/IStoxScript.sol";
import {
    DeclarationCountMismatch,
    DuplicateRecord,
    ForkedLine,
    IdNotScriptPath,
    LibScriptDeclarations,
    MigrationWithoutRecord,
    PrerequisiteCycle,
    UnknownPrerequisite
} from "../../../src/lib/LibScriptDeclarations.sol";

contract LibScriptDeclarationsTest is Test {
    string internal constant A = "script/a.s.sol";
    string internal constant B = "script/b.s.sol";
    string internal constant C = "script/c.s.sol";

    function validate(string[] memory paths, ScriptDeclaration[] memory declarations) external pure {
        LibScriptDeclarations.validate(paths, declarations);
    }

    function id(string memory path) internal pure returns (bytes32) {
        return keccak256(bytes(path));
    }

    function onto(string memory path, bytes32 head) internal pure returns (ScriptDeclaration memory) {
        return ScriptDeclaration({id: id(path), onto: head, history: false});
    }

    function one(string memory path, ScriptDeclaration memory declared)
        internal
        pure
        returns (string[] memory, ScriptDeclaration[] memory)
    {
        string[] memory paths = new string[](1);
        paths[0] = path;
        ScriptDeclaration[] memory declarations = new ScriptDeclaration[](1);
        declarations[0] = declared;
        return (paths, declarations);
    }

    function two(string memory a, ScriptDeclaration memory da, string memory b, ScriptDeclaration memory db)
        internal
        pure
        returns (string[] memory, ScriptDeclaration[] memory)
    {
        string[] memory paths = new string[](2);
        paths[0] = a;
        paths[1] = b;
        ScriptDeclaration[] memory declarations = new ScriptDeclaration[](2);
        declarations[0] = da;
        declarations[1] = db;
        return (paths, declarations);
    }

    function three(
        string memory a,
        ScriptDeclaration memory da,
        string memory b,
        ScriptDeclaration memory db,
        string memory c,
        ScriptDeclaration memory dc
    ) internal pure returns (string[] memory, ScriptDeclaration[] memory) {
        string[] memory paths = new string[](3);
        paths[0] = a;
        paths[1] = b;
        paths[2] = c;
        ScriptDeclaration[] memory declarations = new ScriptDeclaration[](3);
        declarations[0] = da;
        declarations[1] = db;
        declarations[2] = dc;
        return (paths, declarations);
    }

    function expectRevertOn(bytes memory reason, string[] memory paths, ScriptDeclaration[] memory declarations)
        internal
    {
        vm.expectRevert(reason);
        this.validate(paths, declarations);
    }

    function testOneLineFromGenesisPasses() external view {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            three(A, onto(A, MIGRATION_HEAD_GENESIS), B, onto(B, id(A)), C, onto(C, id(B)));
        this.validate(paths, declarations);
    }

    function testALineListedOutOfOrderPasses() external view {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            three(C, onto(C, id(B)), A, onto(A, MIGRATION_HEAD_GENESIS), B, onto(B, id(A)));
        this.validate(paths, declarations);
    }

    function testHistoryDoesNotChangeTheLine() external view {
        ScriptDeclaration memory history = onto(B, id(A));
        history.history = true;
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            two(A, onto(A, MIGRATION_HEAD_GENESIS), B, history);
        this.validate(paths, declarations);
    }

    function testAZeroIdIsNoRecord() external {
        ScriptDeclaration memory declared = onto(A, MIGRATION_HEAD_GENESIS);
        declared.id = 0;
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one(A, declared);
        expectRevertOn(abi.encodeWithSelector(MigrationWithoutRecord.selector, A), paths, declarations);
    }

    function testTheGenesisIdIsNoRecord() external {
        ScriptDeclaration memory declared = onto(A, MIGRATION_HEAD_GENESIS);
        declared.id = MIGRATION_HEAD_GENESIS;
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one(A, declared);
        expectRevertOn(abi.encodeWithSelector(MigrationWithoutRecord.selector, A), paths, declarations);
    }

    function testAnIdThatIsNotItsScriptPathIsRefused() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            one(A, onto("script/other.s.sol", MIGRATION_HEAD_GENESIS));
        expectRevertOn(abi.encodeWithSelector(IdNotScriptPath.selector, A), paths, declarations);
    }

    function testAnIdIsKeyedByTheWholePath() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            one("script/sub/a.s.sol", onto(A, MIGRATION_HEAD_GENESIS));
        expectRevertOn(abi.encodeWithSelector(IdNotScriptPath.selector, "script/sub/a.s.sol"), paths, declarations);
    }

    function testOneScriptListedTwiceIsADuplicateRecord() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            two(A, onto(A, MIGRATION_HEAD_GENESIS), A, onto(A, keccak256("elsewhere")));
        expectRevertOn(abi.encodeWithSelector(DuplicateRecord.selector, A, A), paths, declarations);
    }

    function testTwoMigrationsOntoOneRecordForkTheLine() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            three(A, onto(A, MIGRATION_HEAD_GENESIS), B, onto(B, id(A)), C, onto(C, id(A)));
        expectRevertOn(abi.encodeWithSelector(ForkedLine.selector, C, B), paths, declarations);
    }

    function testTwoMigrationsOntoGenesisForkTheLine() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            two(A, onto(A, MIGRATION_HEAD_GENESIS), B, onto(B, MIGRATION_HEAD_GENESIS));
        expectRevertOn(abi.encodeWithSelector(ForkedLine.selector, B, A), paths, declarations);
    }

    function testAHeadNoScriptDeclaresIsUnknown() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            two(A, onto(A, MIGRATION_HEAD_GENESIS), B, onto(B, id("script/typo.s.sol")));
        expectRevertOn(abi.encodeWithSelector(UnknownPrerequisite.selector, B), paths, declarations);
    }

    function testAZeroHeadIsUnknown() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one(A, onto(A, 0));
        expectRevertOn(abi.encodeWithSelector(UnknownPrerequisite.selector, A), paths, declarations);
    }

    function testALineWithNoGenesisRecordIsUnknownWhereItLeavesTheScripts() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            two(A, onto(A, id(B)), B, onto(B, keccak256("missing")));
        expectRevertOn(abi.encodeWithSelector(UnknownPrerequisite.selector, B), paths, declarations);
    }

    function testAMigrationOntoItselfIsACycle() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one(A, onto(A, id(A)));
        expectRevertOn(abi.encodeWithSelector(PrerequisiteCycle.selector, A), paths, declarations);
    }

    function testTwoMigrationsOntoEachOtherAreACycle() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two(A, onto(A, id(B)), B, onto(B, id(A)));
        expectRevertOn(abi.encodeWithSelector(PrerequisiteCycle.selector, A), paths, declarations);
    }

    function testACycleBesideAGenesisLineIsRefused() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            three(A, onto(A, MIGRATION_HEAD_GENESIS), B, onto(B, id(C)), C, onto(C, id(B)));
        expectRevertOn(abi.encodeWithSelector(PrerequisiteCycle.selector, B), paths, declarations);
    }

    function testEveryDeclarationHasAPath() external {
        (, ScriptDeclaration[] memory declarations) = one(A, onto(A, MIGRATION_HEAD_GENESIS));
        expectRevertOn(abi.encodeWithSelector(DeclarationCountMismatch.selector), new string[](0), declarations);
    }

    function testEveryPathHasADeclaration() external {
        (string[] memory paths,) = two(A, onto(A, MIGRATION_HEAD_GENESIS), B, onto(B, id(A)));
        (, ScriptDeclaration[] memory declarations) = one(A, onto(A, MIGRATION_HEAD_GENESIS));
        expectRevertOn(abi.encodeWithSelector(DeclarationCountMismatch.selector), paths, declarations);
    }
}
