// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {BuildMigrations, HistoryWithoutMoment, ManyDeclarations, NoDeclaration} from "../../script/BuildMigrations.sol";
import {IStoxHistoryMigration, ScriptDeclaration, ScriptKind} from "../../src/interface/IStoxScript.sol";
import {MigrationWithoutRecord} from "../../src/lib/LibScriptDeclarations.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

contract ZeroMomentFixture is IStoxHistoryMigration {
    function executedAt(uint256) external pure returns (uint256) {
        return 0;
    }
}

contract BuildMigrationsHarness is BuildMigrations {
    function callExecutedAt(string memory path, ScriptDeclaration memory declared, address instance, uint256 chainId)
        external
        pure
        returns (uint256)
    {
        return executedAt(path, declared, instance, chainId);
    }
}

contract BuildMigrationsTest is Test {
    string internal constant FIXTURES = "test/fixture/declarations";

    BuildMigrationsHarness internal build = new BuildMigrationsHarness();

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function endsWith(string memory s, string memory suffix) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(suffix);
        if (a.length < b.length) return false;
        for (uint256 i = 0; i < b.length; i++) {
            if (a[a.length - b.length + i] != b[i]) return false;
        }
        return true;
    }

    function lexLess(string memory a, string memory b) internal pure returns (bool) {
        bytes memory x = bytes(a);
        bytes memory y = bytes(b);
        for (uint256 i = 0; i < x.length && i < y.length; i++) {
            if (x[i] != y[i]) return x[i] < y[i];
        }
        return x.length < y.length;
    }

    function index(string memory at, uint256 i) internal pure returns (string memory) {
        return string.concat(at, "[", vm.toString(i), "]");
    }

    function migrationsOf(ScriptDeclaration[] memory declarations) internal pure returns (uint256[] memory rows) {
        uint256 count = 0;
        for (uint256 i = 0; i < declarations.length; i++) {
            if (declarations[i].kind == ScriptKind.Migration) count++;
        }
        rows = new uint256[](count);
        uint256 r = 0;
        for (uint256 i = 0; i < declarations.length; i++) {
            if (declarations[i].kind == ScriptKind.Migration) rows[r++] = i;
        }
    }

    function testVersionIsOne() external {
        assertEq(vm.parseJsonUint(build.render(), ".version"), 1);
    }

    function testGenesisIsTheRegistryGenesis() external {
        assertEq(vm.parseJsonBytes32(build.render(), ".genesis"), MIGRATION_HEAD_GENESIS);
    }

    function testNetworksAreTheDeploymentNetworksWithTheRegistry() external {
        string memory json = build.render();
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
        (string[] memory paths,,) = build.discover("script");
        Vm.DirEntry[] memory entries = vm.readDir("script", 1);
        uint256 scripts = 0;
        for (uint256 e = 0; e < entries.length; e++) {
            if (entries[e].isDir || !endsWith(entries[e].path, ".s.sol")) continue;
            scripts++;
            uint256 hits = 0;
            for (uint256 i = 0; i < paths.length; i++) {
                if (endsWith(entries[e].path, string.concat("/", paths[i]))) hits++;
            }
            assertEq(hits, 1, entries[e].path);
        }
        assertEq(paths.length, scripts);
        for (uint256 i = 1; i < paths.length; i++) {
            assertTrue(lexLess(paths[i - 1], paths[i]), paths[i]);
        }
    }

    function testMigrationsAreTheDeclaredMigrations() external {
        string memory json = build.render();
        (string[] memory paths, ScriptDeclaration[] memory declarations,) = build.discover("script");
        uint256[] memory rows = migrationsOf(declarations);
        assertGt(rows.length, 0);
        assertFalse(vm.keyExistsJson(json, index(".migrations", rows.length)));
        for (uint256 r = 0; r < rows.length; r++) {
            string memory at = index(".migrations", r);
            assertEq(vm.parseJsonString(json, string.concat(at, ".script")), paths[rows[r]]);
            assertEq(vm.parseJsonBytes32(json, string.concat(at, ".namespace")), declarations[rows[r]].namespace);
            assertEq(vm.parseJsonBytes32(json, string.concat(at, ".id")), declarations[rows[r]].id);
        }
    }

    function testChainsAreTheResolvedWriterMomentAndPrerequisites() external {
        string memory json = build.render();
        (, ScriptDeclaration[] memory declarations, address[] memory instances) = build.discover("script");
        uint256[] memory rows = migrationsOf(declarations);
        SupportedNetwork[] memory nets = networks();
        for (uint256 r = 0; r < rows.length; r++) {
            ScriptDeclaration memory d = declarations[rows[r]];
            string memory chains = string.concat(index(".migrations", r), ".chains");
            assertEq(vm.parseJsonKeys(json, chains).length, nets.length);
            for (uint256 c = 0; c < nets.length; c++) {
                assertChain(
                    json,
                    string.concat(chains, ".", vm.toString(nets[c].chainId)),
                    d,
                    instances[rows[r]],
                    nets[c].chainId
                );
            }
        }
    }

    function assertChain(
        string memory json,
        string memory at,
        ScriptDeclaration memory d,
        address instance,
        uint256 chainId
    ) internal view {
        assertEq(
            vm.parseJsonAddress(json, string.concat(at, ".writer")),
            LibStoxMigrations.writerForChainId(d.writer, chainId)
        );
        assertEq(
            vm.parseJsonUint(json, string.concat(at, ".executedAt")),
            d.history ? IStoxHistoryMigration(instance).executedAt(chainId) : 0
        );
        Prerequisite[] memory expected = LibStoxMigrations.prerequisitesForChainId(d, chainId);
        string memory pre = string.concat(at, ".prerequisites");
        assertFalse(vm.keyExistsJson(json, index(pre, expected.length)));
        for (uint256 p = 0; p < expected.length; p++) {
            string memory row = index(pre, p);
            assertEq(vm.parseJsonAddress(json, string.concat(row, ".writer")), expected[p].writer);
            assertEq(vm.parseJsonBytes32(json, string.concat(row, ".namespace")), expected[p].namespace);
            assertEq(vm.parseJsonBytes32(json, string.concat(row, ".id")), expected[p].migration);
        }
    }

    /// @dev Oracle: the per-network moments `governanceTimelockExecution` pins.
    function testTheGovernanceTimelockMoveCarriesItsExecutionMoment() external {
        string memory json = build.render();
        (string[] memory paths, ScriptDeclaration[] memory declarations,) = build.discover("script");
        uint256[] memory rows = migrationsOf(declarations);
        SupportedNetwork[] memory nets = networks();
        uint256 hits = 0;
        for (uint256 r = 0; r < rows.length; r++) {
            bool governance = declarations[rows[r]].id == LibStoxMigrations.GOVERNANCE_TIMELOCK;
            if (governance) {
                hits++;
                assertEq(paths[rows[r]], "script/20260729-migrate-governance-to-timelock.s.sol");
            }
            for (uint256 c = 0; c < nets.length; c++) {
                (uint256 moment,) = LibStoxMigrations.governanceTimelockExecution(nets[c].chainId);
                string memory at =
                    string.concat(index(".migrations", r), ".chains.", vm.toString(nets[c].chainId), ".executedAt");
                assertEq(vm.parseJsonUint(json, at), governance ? moment : 0);
            }
        }
        assertEq(hits, 1);
    }

    function testRunWritesTheRender() external {
        vm.removeFile("migrations.json");
        build.run();
        assertEq(keccak256(vm.parseJson(vm.readFile("migrations.json"))), keccak256(vm.parseJson(build.render())));
    }

    function testAScriptThatDoesNotDeclareItselfFails() external {
        string memory dir = string.concat(FIXTURES, "/undeclared");
        vm.expectRevert(
            abi.encodeWithSelector(NoDeclaration.selector, string.concat(dir, "/UndeclaredScriptFixture.s.sol"))
        );
        build.discover(dir);
    }

    function testAScriptFileWithTwoDeclarationsFails() external {
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
        (string[] memory paths, ScriptDeclaration[] memory declarations, address[] memory instances) =
            build.discover(dir);
        assertEq(paths.length, 1);
        assertEq(paths[0], string.concat(dir, "/ValidDeclarationFixture.s.sol"));
        assertEq(uint256(declarations[0].kind), uint256(ScriptKind.TimelockExecutor));
        assertGt(instances[0].code.length, 0);
    }

    function testAHistoryMigrationWithNoMomentFails() external {
        ScriptDeclaration memory d = LibStoxMigrations.safeMigrationOnto(
            LibStoxMigrations.NAMESPACE, keccak256("script/h.s.sol"), MIGRATION_HEAD_GENESIS, true
        );
        address zero = address(new ZeroMomentFixture());
        vm.expectRevert(abi.encodeWithSelector(HistoryWithoutMoment.selector, "script/h.s.sol", uint256(1)));
        build.callExecutedAt("script/h.s.sol", d, zero, 1);
        address none = address(new BuildMigrations());
        vm.expectRevert(abi.encodeWithSelector(HistoryWithoutMoment.selector, "script/h.s.sol", uint256(1)));
        build.callExecutedAt("script/h.s.sol", d, none, 1);
    }

    function testAMigrationRecordedWithItsChangeHasNoMoment() external {
        ScriptDeclaration memory d = LibStoxMigrations.safeMigrationOnto(
            LibStoxMigrations.NAMESPACE, keccak256("script/h.s.sol"), MIGRATION_HEAD_GENESIS, false
        );
        assertEq(build.callExecutedAt("script/h.s.sol", d, address(new ZeroMomentFixture()), 1), 0);
    }
}
