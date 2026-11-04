// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";

import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

/// @title BuildMigrationsDeclaredTest
/// @notice Every migration the scripts declare, read from `migrations.json`
/// (git-clean regenerates it from `script/` and fails on any drift).
contract BuildMigrationsDeclaredTest is Test {
    string internal constant MANIFEST = "migrations.json";

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function index(string memory at, uint256 i) internal pure returns (string memory) {
        return string.concat(at, "[", vm.toString(i), "]");
    }

    function row(uint256 i) internal pure returns (string memory) {
        return index(".migrations", i);
    }

    function chain(uint256 i, uint256 chainId) internal pure returns (string memory) {
        return string.concat(row(i), ".chains.", vm.toString(chainId));
    }

    function idOf(string memory json, uint256 i) internal pure returns (bytes32) {
        return vm.parseJsonBytes32(json, string.concat(row(i), ".id"));
    }

    function ontoOf(string memory json, uint256 i, uint256 chainId) internal pure returns (bytes32) {
        return vm.parseJsonBytes32(json, string.concat(chain(i, chainId), ".onto"));
    }

    function executedAtOf(string memory json, uint256 i, uint256 chainId) internal pure returns (uint256) {
        return vm.parseJsonUint(json, string.concat(chain(i, chainId), ".executedAt"));
    }

    function manifest() internal view returns (string memory, uint256) {
        string memory json = vm.readFile(MANIFEST);
        uint256 rows = 0;
        while (vm.keyExistsJson(json, row(rows))) rows++;
        assertGt(rows, 0);
        return (json, rows);
    }

    /// @dev Each chain's rows in line order, walked from genesis; fails unless
    /// every row is on the one line.
    function line(string memory json, uint256 rows, uint256 chainId) internal pure returns (uint256[] memory) {
        uint256[] memory order = new uint256[](rows);
        bool[] memory seen = new bool[](rows);
        bytes32 head = MIGRATION_HEAD_GENESIS;
        for (uint256 step = 0; step < rows; step++) {
            uint256 found = type(uint256).max;
            for (uint256 i = 0; i < rows; i++) {
                if (ontoOf(json, i, chainId) != head) continue;
                assertEq(found, type(uint256).max, chain(i, chainId));
                found = i;
            }
            assertNotEq(found, type(uint256).max, string.concat(vm.toString(chainId), ": line ends early"));
            assertFalse(seen[found], chain(found, chainId));
            seen[found] = true;
            order[step] = found;
            head = idOf(json, found);
        }
        return order;
    }

    function testTheManifestIsTheRootLine() external view {
        (string memory json,) = manifest();
        assertEq(vm.parseJsonUint(json, ".version"), 1);
        assertEq(vm.parseJsonBytes32(json, ".genesis"), MIGRATION_HEAD_GENESIS);
        assertEq(vm.parseJsonAddress(json, ".writer"), LibRegistryAuthority.ROOT_AUTHORITY);
        assertEq(vm.parseJsonBytes32(json, ".namespace"), LibStoxMigrations.NAMESPACE);
    }

    function testEveryRowIsAScriptKeyedByItsPath() external view {
        (string memory json, uint256 rows) = manifest();
        for (uint256 i = 0; i < rows; i++) {
            string memory script = vm.parseJsonString(json, string.concat(row(i), ".script"));
            assertTrue(vm.exists(script), script);
            assertEq(idOf(json, i), keccak256(bytes(script)), script);
        }
    }

    function testEveryRowIsDeclaredOnEveryDeploymentNetwork() external view {
        (string memory json, uint256 rows) = manifest();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < rows; i++) {
            assertEq(vm.parseJsonKeys(json, string.concat(row(i), ".chains")).length, nets.length, row(i));
            for (uint256 n = 0; n < nets.length; n++) {
                assertTrue(vm.keyExistsJson(json, chain(i, nets[n].chainId)), chain(i, nets[n].chainId));
            }
        }
    }

    function testEachChainIsOneLineFromGenesis() external view {
        (string memory json, uint256 rows) = manifest();
        SupportedNetwork[] memory nets = networks();
        for (uint256 n = 0; n < nets.length; n++) {
            line(json, rows, nets[n].chainId);
        }
    }

    /// @notice The registry refuses a history moment before its head's, and a
    /// record written now is after every pinned moment, so on each chain's line
    /// every history row precedes every record and the moments never fall.
    function testHistoryPrecedesEveryRecordAndMomentsNeverFall() external view {
        (string memory json, uint256 rows) = manifest();
        SupportedNetwork[] memory nets = networks();
        for (uint256 n = 0; n < nets.length; n++) {
            uint256 chainId = nets[n].chainId;
            uint256[] memory order = line(json, rows, chainId);
            bool recorded = false;
            uint256 last = 0;
            for (uint256 step = 0; step < order.length; step++) {
                uint256 moment = executedAtOf(json, order[step], chainId);
                string memory at = chain(order[step], chainId);
                if (moment == 0) {
                    recorded = true;
                    continue;
                }
                assertFalse(recorded, at);
                assertGe(moment, last, at);
                last = moment;
            }
        }
    }
}
