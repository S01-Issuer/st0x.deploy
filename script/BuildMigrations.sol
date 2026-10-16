// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {IStoxHistoryMigration, IStoxScript, ScriptDeclaration, ScriptKind} from "../src/interface/IStoxScript.sol";
import {LibScriptDeclarations} from "../src/lib/LibScriptDeclarations.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";

/// @notice No contract in a script file declares itself.
/// @param script The script's path.
error NoDeclaration(string script);

/// @notice More than one contract in a script file declares itself.
/// @param script The script's path.
error ManyDeclarations(string script);

/// @notice A migration recorded as history gives no moment on a network.
/// @param script The script's path.
/// @param chainId The chain id.
error HistoryWithoutMoment(string script, uint256 chainId);

/// @title BuildMigrations
/// @notice Reads every `script/*.s.sol`'s own declaration, reverts unless all
/// of them are valid together, and writes `migrations.json`: every migration,
/// and per deployment network the registry and each migration's writer,
/// execution moment if recorded as history, and prerequisites.
contract BuildMigrations is Script {
    string internal constant PATH = "migrations.json";
    string internal constant SCRIPTS = "script";
    string internal constant SUFFIX = ".s.sol";

    function endsWith(string memory s, string memory suffix) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(suffix);
        if (a.length < b.length) return false;
        for (uint256 i = 0; i < b.length; i++) {
            if (a[a.length - b.length + i] != b[i]) return false;
        }
        return true;
    }

    function basename(string memory path) internal pure returns (string memory) {
        bytes memory p = bytes(path);
        uint256 start = 0;
        for (uint256 i = 0; i < p.length; i++) {
            if (p[i] == "/") start = i + 1;
        }
        bytes memory out = new bytes(p.length - start);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = p[start + i];
        }
        return string(out);
    }

    function stem(string memory name, uint256 suffixLength) internal pure returns (string memory) {
        bytes memory n = bytes(name);
        bytes memory out = new bytes(n.length - suffixLength);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = n[i];
        }
        return string(out);
    }

    function before(string memory a, string memory b) internal pure returns (bool) {
        bytes memory x = bytes(a);
        bytes memory y = bytes(b);
        uint256 n = x.length < y.length ? x.length : y.length;
        for (uint256 i = 0; i < n; i++) {
            if (x[i] != y[i]) return x[i] < y[i];
        }
        return x.length < y.length;
    }

    /// @dev Each `.s.sol` in `dir`, by file name.
    function scriptNames(string memory dir) internal view returns (string[] memory) {
        Vm.DirEntry[] memory entries = vm.readDir(dir, 1);
        string[] memory names = new string[](entries.length);
        uint256 count = 0;
        for (uint256 e = 0; e < entries.length; e++) {
            if (entries[e].isDir || !endsWith(entries[e].path, SUFFIX)) continue;
            string memory name = basename(entries[e].path);
            uint256 at = count++;
            while (at > 0 && before(name, names[at - 1])) {
                names[at] = names[at - 1];
                at--;
            }
            names[at] = name;
        }
        assembly ("memory-safe") {
            mstore(names, count)
        }
        return names;
    }

    /// @dev The one contract in `name`'s artifacts that declares itself.
    function declaring(string memory path, string memory name) internal returns (address, ScriptDeclaration memory) {
        Vm.DirEntry[] memory artifacts = vm.readDir(string.concat("out/", name), 1);
        address found;
        ScriptDeclaration memory declared;
        for (uint256 a = 0; a < artifacts.length; a++) {
            string memory artifact = basename(artifacts[a].path);
            if (!endsWith(artifact, ".json")) continue;
            string memory id = string.concat(name, ":", stem(artifact, 5));
            if (vm.getCode(id).length == 0) continue;
            address instance = vm.deployCode(id);
            try IStoxScript(instance).declaration() returns (ScriptDeclaration memory d) {
                if (found != address(0)) revert ManyDeclarations(path);
                found = instance;
                declared = d;
            } catch {}
        }
        if (found == address(0)) revert NoDeclaration(path);
        return (found, declared);
    }

    /// @notice Every script in `dir` with its declaration, in path order;
    /// reverts on a script that does not declare itself, or on any rule
    /// `LibScriptDeclarations` holds the declarations to.
    /// @param dir The directory.
    /// @return paths Each script's path.
    /// @return declarations Each script's declaration.
    /// @return instances Each script's declaring contract, deployed.
    function discover(string memory dir)
        public
        returns (string[] memory paths, ScriptDeclaration[] memory declarations, address[] memory instances)
    {
        string[] memory names = scriptNames(dir);
        paths = new string[](names.length);
        declarations = new ScriptDeclaration[](names.length);
        instances = new address[](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            paths[i] = string.concat(dir, "/", names[i]);
            (instances[i], declarations[i]) = declaring(paths[i], names[i]);
        }
        LibScriptDeclarations.validate(paths, declarations);
    }

    function prerequisitesJson(string memory key, Prerequisite[] memory prerequisites)
        internal
        returns (string[] memory)
    {
        string[] memory rows = new string[](prerequisites.length);
        for (uint256 i = 0; i < prerequisites.length; i++) {
            string memory row = string.concat(key, ".", vm.toString(i));
            vm.serializeAddress(row, "writer", prerequisites[i].writer);
            vm.serializeBytes32(row, "namespace", prerequisites[i].namespace);
            rows[i] = vm.serializeBytes32(row, "id", prerequisites[i].migration);
        }
        return rows;
    }

    function executedAt(string memory path, ScriptDeclaration memory declared, address instance, uint256 chainId)
        internal
        pure
        returns (uint256)
    {
        if (!declared.history) return 0;
        try IStoxHistoryMigration(instance).executedAt(chainId) returns (uint256 moment) {
            if (moment > 0) return moment;
        } catch {}
        revert HistoryWithoutMoment(path, chainId);
    }

    function chainJson(
        string memory key,
        string memory path,
        ScriptDeclaration memory declared,
        address instance,
        uint256 chainId
    ) internal returns (string memory) {
        vm.serializeAddress(key, "writer", LibStoxMigrations.writerForChainId(declared.writer, chainId));
        vm.serializeUint(key, "executedAt", executedAt(path, declared, instance, chainId));
        return vm.serializeString(
            key,
            "prerequisites",
            prerequisitesJson(
                string.concat(key, ".prerequisites"), LibStoxMigrations.prerequisitesForChainId(declared, chainId)
            )
        );
    }

    function migrationJson(
        uint256 index,
        string memory path,
        ScriptDeclaration memory declared,
        address instance,
        SupportedNetwork[] memory networks
    ) internal returns (string memory) {
        string memory key = string.concat("migrations.", vm.toString(index));
        string memory chainsKey = string.concat(key, ".chains");
        string memory chains;
        for (uint256 i = 0; i < networks.length; i++) {
            string memory chainId = vm.toString(networks[i].chainId);
            chains = vm.serializeString(
                chainsKey,
                chainId,
                chainJson(string.concat(chainsKey, ".", chainId), path, declared, instance, networks[i].chainId)
            );
        }
        vm.serializeBytes32(key, "namespace", declared.namespace);
        vm.serializeBytes32(key, "id", declared.id);
        vm.serializeString(key, "script", path);
        return vm.serializeString(key, "chains", chains);
    }

    function render() public returns (string memory) {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        string memory networksJson;
        for (uint256 i = 0; i < networks.length; i++) {
            string memory key = string.concat("networks.", vm.toString(networks[i].chainId));
            vm.serializeString(key, "network", networks[i].name);
            networksJson = vm.serializeString(
                "networks",
                vm.toString(networks[i].chainId),
                vm.serializeAddress(key, "registry", LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            );
        }
        (string[] memory paths, ScriptDeclaration[] memory declarations, address[] memory instances) = discover(SCRIPTS);
        uint256 count = 0;
        for (uint256 i = 0; i < declarations.length; i++) {
            if (declarations[i].kind == ScriptKind.Migration) count++;
        }
        string[] memory rows = new string[](count);
        uint256 row = 0;
        for (uint256 i = 0; i < declarations.length; i++) {
            if (declarations[i].kind != ScriptKind.Migration) continue;
            rows[row] = migrationJson(row, paths[i], declarations[i], instances[i], networks);
            row++;
        }
        vm.serializeUint("root", "version", 1);
        vm.serializeBytes32("root", "genesis", MIGRATION_HEAD_GENESIS);
        vm.serializeString("root", "networks", networksJson);
        return vm.serializeString("root", "migrations", rows);
    }

    function run() external {
        vm.writeJson(render(), PATH);
    }
}
