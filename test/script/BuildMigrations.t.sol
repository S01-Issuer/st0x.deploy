// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import "./AllScripts.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {BuildMigrations, HistoryWithoutMoment, NoDeclaration, ScriptNotBuilt} from "../../script/BuildMigrations.sol";
import {IStoxHistoryMigration, ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {BuildMigrationsHarness} from "./BuildMigrationsHarness.sol";
import {ZeroMomentFixture} from "./ZeroMomentFixture.sol";
import {MigrationWithoutRecord} from "../../src/lib/LibScriptDeclarations.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

contract BuildMigrationsTest is Test, BuildMigrationsHarness {
    string internal constant FIXTURES = "test/fixture/declarations";

    BuildMigrationsHarness internal build = new BuildMigrationsHarness();

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
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

    function discovered()
        internal
        returns (string[] memory paths, ScriptDeclaration[] memory declarations, address[] memory instances)
    {
        return discover("script");
    }

    function migrationsOf(ScriptDeclaration[] memory declarations) internal pure returns (uint256[] memory rows) {
        uint256 count = 0;
        for (uint256 i = 0; i < declarations.length; i++) {
            if (declarations[i].migration) count++;
        }
        rows = new uint256[](count);
        uint256 r = 0;
        for (uint256 i = 0; i < declarations.length; i++) {
            if (declarations[i].migration) rows[r++] = i;
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
        (string[] memory paths,,) = discovered();
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
        (string[] memory paths, ScriptDeclaration[] memory declarations,) = discovered();
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
        (, ScriptDeclaration[] memory declarations, address[] memory instances) = discovered();
        uint256[] memory rows = migrationsOf(declarations);
        SupportedNetwork[] memory nets = networks();
        for (uint256 r = 0; r < rows.length; r++) {
            assertMigrationChains(json, r, declarations[rows[r]], instances[rows[r]], nets);
        }
    }

    function assertMigrationChains(
        string memory json,
        uint256 row,
        ScriptDeclaration memory declared,
        address instance,
        SupportedNetwork[] memory nets
    ) internal view {
        string memory chains = string.concat(index(".migrations", row), ".chains");
        assertEq(vm.parseJsonKeys(json, chains).length, nets.length);
        for (uint256 c = 0; c < nets.length; c++) {
            assertChain(
                json, string.concat(chains, ".", vm.toString(nets[c].chainId)), declared, instance, nets[c].chainId
            );
        }
    }

    function assertChain(
        string memory json,
        string memory at,
        ScriptDeclaration memory declared,
        address instance,
        uint256 chainId
    ) internal view {
        assertEq(
            vm.parseJsonAddress(json, string.concat(at, ".writer")),
            LibStoxMigrations.writerForChainId(declared.writer, chainId)
        );
        uint256 moment = momentOf(declared, instance, chainId);
        assertEq(vm.parseJsonUint(json, string.concat(at, ".executedAt")), moment);
        assertPrerequisitesJson(
            json, string.concat(at, ".prerequisites"), LibStoxMigrations.prerequisitesForChainId(declared, chainId)
        );
    }

    function momentOf(ScriptDeclaration memory declared, address instance, uint256 chainId)
        internal
        pure
        returns (uint256)
    {
        return declared.history ? IStoxHistoryMigration(instance).executedAt(chainId) : 0;
    }

    function assertPrerequisitesJson(string memory json, string memory pre, Prerequisite[] memory expected)
        internal
        view
    {
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
        (string[] memory paths, ScriptDeclaration[] memory declarations,) = discovered();
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

    function testATimelockWrittenLineRendersTheTimelock() external {
        string memory json = build.renderDir(string.concat(FIXTURES, "/timelock"));
        SupportedNetwork[] memory nets = networks();
        assertFalse(vm.keyExistsJson(json, ".migrations[3]"));
        for (uint256 c = 0; c < nets.length; c++) {
            assertTimelockLine(json, nets[c].chainId);
        }
    }

    function assertTimelockLine(string memory json, uint256 chainId) internal pure {
        string memory chain = vm.toString(chainId);
        address safe = LibSafeInvariants.safeForChainId(chainId);
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        assertEq(vm.parseJsonAddress(json, string.concat(".migrations[0].chains.", chain, ".writer")), safe);
        assertEq(vm.parseJsonAddress(json, string.concat(".migrations[1].chains.", chain, ".writer")), timelock);
        string memory second = string.concat(".migrations[2].chains.", chain);
        assertEq(vm.parseJsonAddress(json, string.concat(second, ".writer")), timelock);
        assertEq(vm.parseJsonAddress(json, string.concat(second, ".prerequisites[0].writer")), timelock);
        assertEq(vm.parseJsonBytes32(json, string.concat(second, ".prerequisites[0].id")), "t1");
        assertEq(vm.parseJsonAddress(json, string.concat(second, ".prerequisites[1].writer")), safe);
        assertEq(
            vm.parseJsonBytes32(json, string.concat(second, ".prerequisites[1].namespace")), keccak256("fixture.safe")
        );
        assertEq(vm.parseJsonBytes32(json, string.concat(second, ".prerequisites[1].id")), "s1");
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
        build.runTo(path);
        assertEq(keccak256(vm.parseJson(vm.readFile(path))), keccak256(vm.parseJson(build.render())));
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
        assertFalse(declarations[0].migration);
        assertGt(instances[0].code.length, 0);
    }

    function testAHistoryMigrationWithNoMomentFails() external {
        ScriptDeclaration memory declared = LibStoxMigrations.safeMigrationOnto(
            LibStoxMigrations.NAMESPACE, keccak256("script/h.s.sol"), MIGRATION_HEAD_GENESIS, true
        );
        address zero = address(new ZeroMomentFixture());
        vm.expectRevert(abi.encodeWithSelector(HistoryWithoutMoment.selector, "script/h.s.sol", uint256(1)));
        build.callExecutedAt("script/h.s.sol", declared, zero, 1);
        address none = address(new BuildMigrations());
        vm.expectRevert(abi.encodeWithSelector(HistoryWithoutMoment.selector, "script/h.s.sol", uint256(1)));
        build.callExecutedAt("script/h.s.sol", declared, none, 1);
    }

    function testAMigrationRecordedWithItsChangeHasNoMoment() external {
        ScriptDeclaration memory declared = LibStoxMigrations.safeMigrationOnto(
            LibStoxMigrations.NAMESPACE, keccak256("script/h.s.sol"), MIGRATION_HEAD_GENESIS, false
        );
        assertEq(build.callExecutedAt("script/h.s.sol", declared, address(new ZeroMomentFixture()), 1), 0);
    }
}
