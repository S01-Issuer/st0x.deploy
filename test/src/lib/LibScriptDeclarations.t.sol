// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.22/src/interface/IMigrationRegistryV3.sol";

import {ScriptDeclaration} from "../../../src/interface/IStoxScript.sol";
import {
    DeclarationCountMismatch,
    ForkedLine,
    HeadCycle,
    IdNotScriptPath,
    LibScriptDeclarations,
    MigrationWithoutRecord,
    RecordOnNonMigration,
    UnknownHead
} from "../../../src/lib/LibScriptDeclarations.sol";
import {LibStoxMigrations} from "../../../src/lib/LibStoxMigrations.sol";

/// @title LibScriptDeclarationsTest
/// @notice The declared migrations form one line from genesis: each id is its
/// script's path, each head is genesis or another declared migration, no two
/// share a head, and following heads always reaches genesis.
contract LibScriptDeclarationsTest is Test {
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

    function three(
        string memory a,
        ScriptDeclaration memory da,
        string memory b,
        ScriptDeclaration memory db,
        string memory c,
        ScriptDeclaration memory dc
    ) internal pure returns (string[] memory paths, ScriptDeclaration[] memory declarations) {
        paths = new string[](3);
        paths[0] = a;
        paths[1] = b;
        paths[2] = c;
        declarations = new ScriptDeclaration[](3);
        declarations[0] = da;
        declarations[1] = db;
        declarations[2] = dc;
    }

    function onto(string memory path, bytes32 head) internal pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.migrationOnto(keccak256(bytes(path)), head);
    }

    function expectRevertOn(bytes memory reason, string[] memory paths, ScriptDeclaration[] memory declarations)
        internal
    {
        vm.expectRevert(reason);
        this.validate(paths, declarations);
    }

    function testALineFromGenesisPasses() external view {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = three(
            "script/a.s.sol",
            onto("script/a.s.sol", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            onto("script/b.s.sol", keccak256("script/a.s.sol")),
            "script/c.s.sol",
            onto("script/c.s.sol", keccak256("script/b.s.sol"))
        );
        this.validate(paths, declarations);
    }

    /// @notice A head may be declared after the migration onto it.
    function testALineOutOfPathOrderPasses() external view {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two(
            "script/a.s.sol",
            onto("script/a.s.sol", keccak256("script/b.s.sol")),
            "script/b.s.sol",
            onto("script/b.s.sol", MIGRATION_HEAD_GENESIS)
        );
        this.validate(paths, declarations);
    }

    function testANonMigrationWithNoRecordPasses() external view {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            one("script/a.s.sol", LibStoxMigrations.notAMigration());
        this.validate(paths, declarations);
    }

    function testNoScriptsPass() external view {
        this.validate(new string[](0), new ScriptDeclaration[](0));
    }

    function testAMigrationWithNoIdIsRefused() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            one("script/a.s.sol", LibStoxMigrations.migrationOnto(0, MIGRATION_HEAD_GENESIS));
        expectRevertOn(abi.encodeWithSelector(MigrationWithoutRecord.selector, "script/a.s.sol"), paths, declarations);
    }

    function testTheGenesisIdIsNoRecord() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            one("script/a.s.sol", LibStoxMigrations.migrationOnto(MIGRATION_HEAD_GENESIS, MIGRATION_HEAD_GENESIS));
        expectRevertOn(abi.encodeWithSelector(MigrationWithoutRecord.selector, "script/a.s.sol"), paths, declarations);
    }

    function testAnIdThatIsNotTheScriptPathIsRefused() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            one("script/a.s.sol", onto("script/b.s.sol", MIGRATION_HEAD_GENESIS));
        expectRevertOn(abi.encodeWithSelector(IdNotScriptPath.selector, "script/a.s.sol"), paths, declarations);
    }

    function testANonMigrationWithAnIdIsRefused() external {
        ScriptDeclaration memory declared = LibStoxMigrations.notAMigration();
        declared.id = keccak256("script/a.s.sol");
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one("script/a.s.sol", declared);
        expectRevertOn(abi.encodeWithSelector(RecordOnNonMigration.selector, "script/a.s.sol"), paths, declarations);
    }

    function testANonMigrationWithAHeadIsRefused() external {
        ScriptDeclaration memory declared = LibStoxMigrations.notAMigration();
        declared.onto = MIGRATION_HEAD_GENESIS;
        (string[] memory paths, ScriptDeclaration[] memory declarations) = one("script/a.s.sol", declared);
        expectRevertOn(abi.encodeWithSelector(RecordOnNonMigration.selector, "script/a.s.sol"), paths, declarations);
    }

    function testAnInvalidNonMigrationFailsBeforeAnyLineRule() external {
        ScriptDeclaration memory declared = LibStoxMigrations.notAMigration();
        declared.onto = MIGRATION_HEAD_GENESIS;
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two(
            "script/a.s.sol", onto("script/a.s.sol", keccak256("missing")), "script/b.s.sol", declared
        );
        expectRevertOn(abi.encodeWithSelector(RecordOnNonMigration.selector, "script/b.s.sol"), paths, declarations);
    }

    function testAHeadNoScriptDeclaresIsUnknown() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two(
            "script/a.s.sol",
            onto("script/a.s.sol", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            onto("script/b.s.sol", keccak256("script/missing.s.sol"))
        );
        expectRevertOn(abi.encodeWithSelector(UnknownHead.selector, "script/b.s.sol"), paths, declarations);
    }

    /// @notice Zero is no record, and a non-migration's empty id is not a
    /// head.
    function testAZeroHeadIsUnknownBesideANonMigration() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two(
            "script/a.s.sol", LibStoxMigrations.notAMigration(), "script/b.s.sol", onto("script/b.s.sol", 0)
        );
        expectRevertOn(abi.encodeWithSelector(UnknownHead.selector, "script/b.s.sol"), paths, declarations);
    }

    function testTwoMigrationsOntoGenesisForkTheLine() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two(
            "script/a.s.sol",
            onto("script/a.s.sol", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            onto("script/b.s.sol", MIGRATION_HEAD_GENESIS)
        );
        expectRevertOn(
            abi.encodeWithSelector(ForkedLine.selector, "script/b.s.sol", "script/a.s.sol"), paths, declarations
        );
    }

    function testTwoMigrationsOntoOneMigrationForkTheLine() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = three(
            "script/a.s.sol",
            onto("script/a.s.sol", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            onto("script/b.s.sol", keccak256("script/a.s.sol")),
            "script/c.s.sol",
            onto("script/c.s.sol", keccak256("script/a.s.sol"))
        );
        expectRevertOn(
            abi.encodeWithSelector(ForkedLine.selector, "script/c.s.sol", "script/b.s.sol"), paths, declarations
        );
    }

    function testAMigrationIsNotItsOwnHead() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) =
            one("script/a.s.sol", onto("script/a.s.sol", keccak256("script/a.s.sol")));
        expectRevertOn(abi.encodeWithSelector(HeadCycle.selector, "script/a.s.sol"), paths, declarations);
    }

    function testACycleOfHeadsIsRefused() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = two(
            "script/a.s.sol",
            onto("script/a.s.sol", keccak256("script/b.s.sol")),
            "script/b.s.sol",
            onto("script/b.s.sol", keccak256("script/a.s.sol"))
        );
        expectRevertOn(abi.encodeWithSelector(HeadCycle.selector, "script/a.s.sol"), paths, declarations);
    }

    /// @notice A cycle beside a line from genesis is still a cycle.
    function testACycleBesideALineIsRefused() external {
        (string[] memory paths, ScriptDeclaration[] memory declarations) = three(
            "script/a.s.sol",
            onto("script/a.s.sol", MIGRATION_HEAD_GENESIS),
            "script/b.s.sol",
            onto("script/b.s.sol", keccak256("script/c.s.sol")),
            "script/c.s.sol",
            onto("script/c.s.sol", keccak256("script/b.s.sol"))
        );
        expectRevertOn(abi.encodeWithSelector(HeadCycle.selector, "script/b.s.sol"), paths, declarations);
    }

    function testEveryDeclarationHasAPath() external {
        (, ScriptDeclaration[] memory declarations) =
            one("script/a.s.sol", onto("script/a.s.sol", MIGRATION_HEAD_GENESIS));
        vm.expectRevert(abi.encodeWithSelector(DeclarationCountMismatch.selector));
        this.validate(new string[](0), declarations);
    }
}
