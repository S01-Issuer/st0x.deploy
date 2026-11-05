// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
// Discovery reads build artifacts, and forge test builds only what a test imports.
import {AForkedOffBaseGenesisFixture} from "../fixture/declarations/forked-off-base/AForkedOffBaseGenesisFixture.s.sol";
import {BForkedOffBaseFixture} from "../fixture/declarations/forked-off-base/BForkedOffBaseFixture.s.sol";
import {InvalidDeclarationFixture} from "../fixture/declarations/invalid/InvalidDeclarationFixture.s.sol";
import {ALineGenesisFixture} from "../fixture/declarations/line/ALineGenesisFixture.s.sol";
import {BLineBaseHistoryFixture} from "../fixture/declarations/line/BLineBaseHistoryFixture.s.sol";
import {CLineHistoryEverywhereFixture} from "../fixture/declarations/line/CLineHistoryEverywhereFixture.s.sol";
import {ManyDeclarationsFixture} from "../fixture/declarations/many/ManyDeclarationsFixture.s.sol";
import {UndeclaredScriptFixture} from "../fixture/declarations/undeclared/UndeclaredScriptFixture.s.sol";
import {ValidDeclarationFixture} from "../fixture/declarations/valid/ValidDeclarationFixture.s.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {
    BuildMigrations,
    HistoryWithoutMoment,
    ManyDeclarations,
    NoDeclaration,
    NoDeploymentNetworks,
    ScriptNotBuilt
} from "../../script/BuildMigrations.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {BuildMigrationsHarness} from "./BuildMigrationsHarness.sol";
import {ZeroMomentFixture} from "./ZeroMomentFixture.sol";
import {ForkedLine, MigrationWithoutRecord} from "../../src/lib/LibScriptDeclarations.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

contract BuildMigrationsTest is Test {
    string internal constant FIXTURES = "test/fixture/declarations";
    string internal constant LINE = "test/fixture/declarations/line";
    string internal constant A = "test/fixture/declarations/line/ALineGenesisFixture.s.sol";
    string internal constant B = "test/fixture/declarations/line/BLineBaseHistoryFixture.s.sol";
    string internal constant C = "test/fixture/declarations/line/CLineHistoryEverywhereFixture.s.sol";

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

    function chainAt(uint256 row, uint256 chainId) internal pure returns (string memory) {
        return string.concat(index(".migrations", row), ".chains.", vm.toString(chainId));
    }

    function testVersionIsOne() external {
        assertEq(vm.parseJsonUint(build.renderDir(LINE), ".version"), 1);
    }

    function testGenesisIsTheRegistryGenesis() external {
        assertEq(vm.parseJsonBytes32(build.renderDir(LINE), ".genesis"), MIGRATION_HEAD_GENESIS);
    }

    function testTheLineIsTheRootAuthorityInTheStoxNamespace() external {
        string memory json = build.renderDir(LINE);
        assertEq(vm.parseJsonAddress(json, ".writer"), LibRegistryAuthority.ROOT_AUTHORITY);
        assertEq(vm.parseJsonBytes32(json, ".namespace"), LibStoxMigrations.NAMESPACE);
    }

    function testNetworksAreTheDeploymentNetworksWithTheRegistry() external {
        string memory json = build.renderDir(LINE);
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
        (string[] memory paths,,) = build.discover(LINE, LibSafeInvariants.BASE_CHAIN_ID);
        Vm.DirEntry[] memory entries = vm.readDir(LINE, 1);
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

    function testEveryScriptIsARowKeyedByItsPath() external {
        string memory json = build.renderDir(LINE);
        string[3] memory scripts = [A, B, C];
        assertFalse(vm.keyExistsJson(json, index(".migrations", scripts.length)));
        for (uint256 i = 0; i < scripts.length; i++) {
            string memory at = index(".migrations", i);
            assertEq(vm.parseJsonString(json, string.concat(at, ".script")), scripts[i]);
            assertEq(vm.parseJsonBytes32(json, string.concat(at, ".id")), keccak256(bytes(scripts[i])));
        }
    }

    function assertChain(string memory json, uint256 row, uint256 chainId, bytes32 head, uint256 moment) internal pure {
        string memory at = chainAt(row, chainId);
        assertEq(vm.parseJsonBytes32(json, string.concat(at, ".onto")), head, at);
        assertEq(vm.parseJsonUint(json, string.concat(at, ".executedAt")), moment, at);
    }

    function testEachChainRendersItsOwnHeadAndMoment() external {
        string memory json = build.renderDir(LINE);
        SupportedNetwork[] memory nets = networks();
        for (uint256 row = 0; row < 3; row++) {
            assertEq(vm.parseJsonKeys(json, string.concat(index(".migrations", row), ".chains")).length, nets.length);
        }
        for (uint256 n = 0; n < nets.length; n++) {
            uint256 chainId = nets[n].chainId;
            assertChain(json, 0, chainId, MIGRATION_HEAD_GENESIS, 0);
            if (chainId == LibSafeInvariants.BASE_CHAIN_ID) {
                assertChain(json, 1, chainId, keccak256(bytes(A)), 1_700_000_000);
                assertChain(json, 2, chainId, keccak256(bytes(B)), 1_800_000_000 + chainId);
            } else {
                assertChain(json, 1, chainId, keccak256(bytes(C)), 0);
                assertChain(json, 2, chainId, keccak256(bytes(A)), 1_800_000_000 + chainId);
            }
        }
    }

    function testEveryDeploymentNetworkIsValidated() external {
        string memory dir = string.concat(FIXTURES, "/forked-off-base");
        build.discover(dir, LibSafeInvariants.BASE_CHAIN_ID);
        vm.expectRevert(
            abi.encodeWithSelector(
                ForkedLine.selector,
                string.concat(dir, "/BForkedOffBaseFixture.s.sol"),
                string.concat(dir, "/AForkedOffBaseGenesisFixture.s.sol")
            )
        );
        build.renderDir(dir);
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
        build.runTo(LINE, path);
        assertEq(keccak256(vm.parseJson(vm.readFile(path))), keccak256(vm.parseJson(build.renderDir(LINE))));
    }

    function testNoDeploymentNetworkFails() external {
        vm.expectRevert(abi.encodeWithSelector(NoDeploymentNetworks.selector));
        build.callRenderFor(LINE, new SupportedNetwork[](0));
    }

    function testAScriptWithNoArtifactsFails() external {
        vm.expectRevert(abi.encodeWithSelector(ScriptNotBuilt.selector, "script/NoSuchScript.s.sol"));
        build.callDeclaring("script/NoSuchScript.s.sol", "NoSuchScript.s.sol", LibSafeInvariants.BASE_CHAIN_ID);
    }

    function testAScriptThatDoesNotDeclareItselfFails() external {
        string memory dir = string.concat(FIXTURES, "/undeclared");
        vm.expectRevert(
            abi.encodeWithSelector(NoDeclaration.selector, string.concat(dir, "/UndeclaredScriptFixture.s.sol"))
        );
        build.discover(dir, LibSafeInvariants.BASE_CHAIN_ID);
    }

    function testTwoDeclaringContractsInOneFileFail() external {
        string memory dir = string.concat(FIXTURES, "/many");
        vm.expectRevert(
            abi.encodeWithSelector(ManyDeclarations.selector, string.concat(dir, "/ManyDeclarationsFixture.s.sol"))
        );
        build.discover(dir, LibSafeInvariants.BASE_CHAIN_ID);
    }

    function testAnInvalidDeclarationFails() external {
        string memory dir = string.concat(FIXTURES, "/invalid");
        vm.expectRevert(
            abi.encodeWithSelector(
                MigrationWithoutRecord.selector, string.concat(dir, "/InvalidDeclarationFixture.s.sol")
            )
        );
        build.discover(dir, LibSafeInvariants.BASE_CHAIN_ID);
    }

    function testOnlyScriptFilesAreReadAndInterfacesAreSkipped() external {
        string memory dir = string.concat(FIXTURES, "/valid");
        (string[] memory paths, ScriptDeclaration[] memory declarations, address[] memory instances) =
            build.discover(dir, LibSafeInvariants.BASE_CHAIN_ID);
        assertEq(paths.length, 1);
        assertEq(paths[0], string.concat(dir, "/ValidDeclarationFixture.s.sol"));
        assertEq(declarations[0].id, keccak256(bytes(paths[0])));
        assertGt(instances[0].code.length, 0);
    }

    function testAHistoryMigrationWithNoMomentFails() external {
        ScriptDeclaration memory declared =
            ScriptDeclaration({id: keccak256("script/h.s.sol"), onto: MIGRATION_HEAD_GENESIS, history: true});
        address zero = address(new ZeroMomentFixture());
        vm.expectRevert(abi.encodeWithSelector(HistoryWithoutMoment.selector, "script/h.s.sol", uint256(1)));
        build.callExecutedAt("script/h.s.sol", declared, zero, 1);
        address none = address(new BuildMigrations());
        vm.expectRevert(abi.encodeWithSelector(HistoryWithoutMoment.selector, "script/h.s.sol", uint256(1)));
        build.callExecutedAt("script/h.s.sol", declared, none, 1);
    }

    function testAMigrationRecordedWithItsChangeHasNoMoment() external {
        ScriptDeclaration memory declared =
            ScriptDeclaration({id: keccak256("script/h.s.sol"), onto: MIGRATION_HEAD_GENESIS, history: false});
        assertEq(build.callExecutedAt("script/h.s.sol", declared, address(new ZeroMomentFixture()), 1), 0);
    }
}
