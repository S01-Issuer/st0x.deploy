// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
// Discovery reads build artifacts, and forge test builds only what a test imports.
import {InvalidDeclarationFixture} from "../fixture/declarations/invalid/InvalidDeclarationFixture.s.sol";
import {ManyDeclarationsFixture} from "../fixture/declarations/many/ManyDeclarationsFixture.s.sol";
import {ALineFirstFixture} from "../fixture/declarations/line/ALineFirstFixture.s.sol";
import {BNotAMigrationFixture} from "../fixture/declarations/line/BNotAMigrationFixture.s.sol";
import {CLineSecondFixture} from "../fixture/declarations/line/CLineSecondFixture.s.sol";
import {UndeclaredScriptFixture} from "../fixture/declarations/undeclared/UndeclaredScriptFixture.s.sol";
import {ValidDeclarationFixture} from "../fixture/declarations/valid/ValidDeclarationFixture.s.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "rain-deploy-0.1.25/src/interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.25/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.25/src/lib/LibRainDeploy.sol";
import {
    BuildMigrations,
    ManyDeclarations,
    NoDeclaration,
    NoDeploymentNetworks,
    ScriptNotBuilt
} from "../../script/BuildMigrations.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {BuildMigrationsHarness} from "./BuildMigrationsHarness.sol";
import {MigrationWithoutRecord} from "../../src/lib/LibScriptDeclarations.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

contract BuildMigrationsTest is Test {
    string internal constant FIXTURES = "test/fixture/declarations";
    string internal constant LINES = "test/fixture/declarations/line";

    BuildMigrationsHarness internal build = new BuildMigrationsHarness();

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function endsWith(string memory text, string memory suffix) internal pure returns (bool) {
        bytes memory textBytes = bytes(text);
        bytes memory suffixBytes = bytes(suffix);
        if (textBytes.length < suffixBytes.length) return false;
        for (uint256 i = 0; i < suffixBytes.length; i++) {
            if (textBytes[textBytes.length - suffixBytes.length + i] != suffixBytes[i]) return false;
        }
        return true;
    }

    function lexLess(string memory left, string memory right) internal pure returns (bool) {
        bytes memory leftBytes = bytes(left);
        bytes memory rightBytes = bytes(right);
        for (uint256 i = 0; i < leftBytes.length && i < rightBytes.length; i++) {
            if (leftBytes[i] != rightBytes[i]) return leftBytes[i] < rightBytes[i];
        }
        return leftBytes.length < rightBytes.length;
    }

    function index(string memory at, uint256 i) internal pure returns (string memory) {
        return string.concat(at, "[", vm.toString(i), "]");
    }

    function discovered() internal returns (string[] memory paths, ScriptDeclaration[] memory declarations) {
        return build.discover(LINES);
    }

    function migrationsOf(ScriptDeclaration[] memory declarations) internal pure returns (uint256[] memory rows) {
        uint256 count = 0;
        for (uint256 i = 0; i < declarations.length; i++) {
            if (declarations[i].migration) count++;
        }
        rows = new uint256[](count);
        uint256 rowIndex = 0;
        for (uint256 i = 0; i < declarations.length; i++) {
            if (declarations[i].migration) rows[rowIndex++] = i;
        }
    }

    function testVersionIsOne() external {
        assertEq(vm.parseJsonUint(build.renderDir(LINES), ".version"), 1);
    }

    function testGenesisIsTheRegistryGenesis() external {
        assertEq(vm.parseJsonBytes32(build.renderDir(LINES), ".genesis"), MIGRATION_HEAD_GENESIS);
    }

    function testNetworksAreTheDeploymentNetworksWithTheRegistry() external {
        string memory json = build.renderDir(LINES);
        SupportedNetwork[] memory nets = networks();
        assertEq(vm.parseJsonKeys(json, ".networks").length, nets.length);
        for (uint256 i = 0; i < nets.length; i++) {
            string memory at = string.concat(".networks.", vm.toString(nets[i].chainId));
            assertEq(vm.parseJsonString(json, string.concat(at, ".network")), nets[i].name);
            assertEq(
                vm.parseJsonAddress(json, string.concat(at, ".registry")),
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS
            );
        }
    }

    function testEveryScriptFileIsDiscoveredInPathOrder() external {
        (string[] memory paths,) = discovered();
        Vm.DirEntry[] memory entries = vm.readDir(LINES, 1);
        uint256 scripts = 0;
        for (uint256 entryIndex = 0; entryIndex < entries.length; entryIndex++) {
            if (entries[entryIndex].isDir || !endsWith(entries[entryIndex].path, ".s.sol")) continue;
            scripts++;
            uint256 hits = 0;
            for (uint256 i = 0; i < paths.length; i++) {
                if (endsWith(entries[entryIndex].path, string.concat("/", paths[i]))) hits++;
            }
            assertEq(hits, 1, entries[entryIndex].path);
        }
        assertEq(paths.length, scripts);
        for (uint256 i = 1; i < paths.length; i++) {
            assertTrue(lexLess(paths[i - 1], paths[i]), paths[i]);
        }
    }

    function testMigrationsAreTheDeclaredMigrations() external {
        string memory json = build.renderDir(LINES);
        (string[] memory paths, ScriptDeclaration[] memory declarations) = discovered();
        uint256[] memory rows = migrationsOf(declarations);
        assertGt(rows.length, 0);
        assertFalse(vm.keyExistsJson(json, index(".migrations", rows.length)));
        for (uint256 rowIndex = 0; rowIndex < rows.length; rowIndex++) {
            string memory at = index(".migrations", rowIndex);
            assertEq(vm.parseJsonString(json, string.concat(at, ".script")), paths[rows[rowIndex]]);
            assertEq(vm.parseJsonBytes32(json, string.concat(at, ".namespace")), LibStoxMigrations.NAMESPACE);
            assertEq(vm.parseJsonBytes32(json, string.concat(at, ".id")), declarations[rows[rowIndex]].id);
        }
    }

    /// @notice Every chain of every migration is the root authority's record,
    /// executed with its change, onto its declared head in the root line.
    function testChainsAreTheRootLineOntoTheDeclaredHead() external {
        string memory json = build.renderDir(LINES);
        (, ScriptDeclaration[] memory declarations) = discovered();
        uint256[] memory rows = migrationsOf(declarations);
        SupportedNetwork[] memory nets = networks();
        for (uint256 rowIndex = 0; rowIndex < rows.length; rowIndex++) {
            string memory chains = string.concat(index(".migrations", rowIndex), ".chains");
            assertEq(vm.parseJsonKeys(json, chains).length, nets.length);
            for (uint256 netIndex = 0; netIndex < nets.length; netIndex++) {
                assertChain(
                    json,
                    string.concat(chains, ".", vm.toString(nets[netIndex].chainId)),
                    declarations[rows[rowIndex]].onto
                );
            }
        }
    }

    function assertChain(string memory json, string memory at, bytes32 head) internal view {
        assertEq(vm.parseJsonAddress(json, string.concat(at, ".writer")), LibStoxMigrations.WRITER);
        assertEq(vm.parseJsonUint(json, string.concat(at, ".executedAt")), 0);
        string memory pre = string.concat(at, ".prerequisites");
        assertFalse(vm.keyExistsJson(json, index(pre, 1)));
        string memory first = index(pre, 0);
        assertEq(vm.parseJsonAddress(json, string.concat(first, ".writer")), LibStoxMigrations.WRITER);
        assertEq(vm.parseJsonBytes32(json, string.concat(first, ".namespace")), LibStoxMigrations.NAMESPACE);
        assertEq(vm.parseJsonBytes32(json, string.concat(first, ".id")), head);
    }

    /// @notice The fixture line renders its two records, the second onto the
    /// first, and skips the script that records nothing.
    function testTheFixtureLineRendersInOrder() external {
        string memory json = build.renderDir(LINES);
        string memory firstPath = string.concat(LINES, "/ALineFirstFixture.s.sol");
        string memory secondPath = string.concat(LINES, "/CLineSecondFixture.s.sol");
        assertFalse(vm.keyExistsJson(json, ".migrations[2]"));
        assertEq(vm.parseJsonString(json, ".migrations[0].script"), firstPath);
        assertEq(vm.parseJsonBytes32(json, ".migrations[0].id"), keccak256(bytes(firstPath)));
        assertEq(vm.parseJsonString(json, ".migrations[1].script"), secondPath);
        assertEq(vm.parseJsonBytes32(json, ".migrations[1].id"), keccak256(bytes(secondPath)));
        SupportedNetwork[] memory nets = networks();
        for (uint256 netIndex = 0; netIndex < nets.length; netIndex++) {
            string memory chain = vm.toString(nets[netIndex].chainId);
            assertEq(
                vm.parseJsonBytes32(json, string.concat(".migrations[0].chains.", chain, ".prerequisites[0].id")),
                MIGRATION_HEAD_GENESIS
            );
            assertEq(
                vm.parseJsonBytes32(json, string.concat(".migrations[1].chains.", chain, ".prerequisites[0].id")),
                keccak256(bytes(firstPath))
            );
        }
    }

    function testBeforeOrdersByBytesThenLength() external view {
        assertTrue(build.callBefore("a", "b"));
        assertFalse(build.callBefore("b", "a"));
        assertTrue(build.callBefore("B", "a"));
        assertTrue(build.callBefore("ab", "abc"));
        assertFalse(build.callBefore("abc", "ab"));
        assertFalse(build.callBefore("ab", "ab"));
    }

    function testSortedOrdersAnyListing() external view {
        string[] memory names = new string[](4);
        names[0] = "c.s.sol";
        names[1] = "ab.s.sol";
        names[2] = "a.s.sol";
        names[3] = "a.s.sol.s.sol";
        string[] memory got = build.callSorted(names);
        assertEq(got[0], "a.s.sol");
        assertEq(got[1], "a.s.sol.s.sol");
        assertEq(got[2], "ab.s.sol");
        assertEq(got[3], "c.s.sol");
    }

    function testRunToWritesTheRender() external {
        string memory path = "out/migrations.test.json";
        if (vm.exists(path)) vm.removeFile(path);
        build.runTo(LINES, path);
        assertEq(keccak256(vm.parseJson(vm.readFile(path))), keccak256(vm.parseJson(build.renderDir(LINES))));
    }

    function testNoDeploymentNetworkFails() external {
        vm.expectRevert(abi.encodeWithSelector(NoDeploymentNetworks.selector));
        build.callRenderFor(LINES, new SupportedNetwork[](0));
    }

    function testAScriptWithNoArtifactsFails() external {
        vm.expectRevert(abi.encodeWithSelector(ScriptNotBuilt.selector, "script/NoSuchScript.s.sol"));
        build.callDeclaring("script/NoSuchScript.s.sol", "NoSuchScript.s.sol");
    }

    function testAScriptThatDoesNotDeclareItselfFails() external {
        string memory dir = string.concat(FIXTURES, "/undeclared");
        vm.expectRevert(
            abi.encodeWithSelector(NoDeclaration.selector, string.concat(dir, "/UndeclaredScriptFixture.s.sol"))
        );
        build.discover(dir);
    }

    function testTwoDeclaringContractsInOneFileFail() external {
        string memory dir = string.concat(FIXTURES, "/many");
        vm.expectRevert(
            abi.encodeWithSelector(ManyDeclarations.selector, string.concat(dir, "/ManyDeclarationsFixture.s.sol"))
        );
        build.discover(dir);
    }

    function testAnInvalidDeclarationFails() external {
        string memory dir = string.concat(FIXTURES, "/invalid");
        vm.expectRevert(
            abi.encodeWithSelector(
                MigrationWithoutRecord.selector, string.concat(dir, "/InvalidDeclarationFixture.s.sol")
            )
        );
        build.discover(dir);
    }

    function testOnlyScriptFilesAreReadAndInterfacesAreSkipped() external {
        string memory dir = string.concat(FIXTURES, "/valid");
        (string[] memory paths, ScriptDeclaration[] memory declarations) = build.discover(dir);
        assertEq(paths.length, 1);
        assertEq(paths[0], string.concat(dir, "/ValidDeclarationFixture.s.sol"));
        assertFalse(declarations[0].migration);
    }
}
