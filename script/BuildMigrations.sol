// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "rain-deploy-0.1.29/src/interface/IMigrationRegistryV5.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.29/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {IStoxHistoryMigration, IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibScriptDeclarations} from "../src/lib/LibScriptDeclarations.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";

/// @notice No contract in a script file declares itself.
/// @param script The script's path.
error NoDeclaration(string script);

/// @notice A script file has no build artifacts: `forge build` has not compiled it.
/// @param script The script's path.
error ScriptNotBuilt(string script);

/// @notice More than one contract in a script file declares itself.
/// @param script The script's path.
error ManyDeclarations(string script);

/// @notice The deployment network catalogue is empty, so the manifest would list
/// no network and no chain.
error NoDeploymentNetworks();

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

    function endsWith(string memory text, string memory suffix) internal pure returns (bool) {
        bytes memory textBytes = bytes(text);
        bytes memory suffixBytes = bytes(suffix);
        if (textBytes.length < suffixBytes.length) return false;
        for (uint256 i = 0; i < suffixBytes.length; i++) {
            if (textBytes[textBytes.length - suffixBytes.length + i] != suffixBytes[i]) return false;
        }
        return true;
    }

    function basename(string memory path) internal pure returns (string memory) {
        bytes memory pathBytes = bytes(path);
        uint256 start = 0;
        for (uint256 i = 0; i < pathBytes.length; i++) {
            if (pathBytes[i] == "/") start = i + 1;
        }
        bytes memory nameBytes = new bytes(pathBytes.length - start);
        for (uint256 i = 0; i < nameBytes.length; i++) {
            nameBytes[i] = pathBytes[start + i];
        }
        return string(nameBytes);
    }

    function stem(string memory name, uint256 suffixLength) internal pure returns (string memory) {
        bytes memory nameBytes = bytes(name);
        bytes memory stemBytes = new bytes(nameBytes.length - suffixLength);
        for (uint256 i = 0; i < stemBytes.length; i++) {
            stemBytes[i] = nameBytes[i];
        }
        return string(stemBytes);
    }

    /// @dev Byte order, a strict prefix first.
    function before(string memory left, string memory right) internal pure returns (bool) {
        bytes memory leftBytes = bytes(left);
        bytes memory rightBytes = bytes(right);
        uint256 shorter = leftBytes.length < rightBytes.length ? leftBytes.length : rightBytes.length;
        for (uint256 i = 0; i < shorter; i++) {
            if (leftBytes[i] != rightBytes[i]) return leftBytes[i] < rightBytes[i];
        }
        return leftBytes.length < rightBytes.length;
    }

    /// @dev `names` in `before` order, whatever order the filesystem lists.
    function sorted(string[] memory names) internal pure returns (string[] memory) {
        for (uint256 i = 1; i < names.length; i++) {
            string memory name = names[i];
            uint256 at = i;
            while (at > 0 && before(name, names[at - 1])) {
                names[at] = names[at - 1];
                at--;
            }
            names[at] = name;
        }
        return names;
    }

    /// @dev Each `.s.sol` in `dir`, by file name.
    function scriptNames(string memory dir) internal view returns (string[] memory) {
        Vm.DirEntry[] memory entries = vm.readDir(dir, 1);
        string[] memory names = new string[](entries.length);
        uint256 count = 0;
        for (uint256 entry = 0; entry < entries.length; entry++) {
            if (entries[entry].isDir || !endsWith(entries[entry].path, SUFFIX)) continue;
            names[count++] = basename(entries[entry].path);
        }
        assembly ("memory-safe") {
            mstore(names, count)
        }
        return sorted(names);
    }

    /// @dev The one contract in `name`'s artifacts that declares itself.
    function declaring(string memory path, string memory name) internal returns (address, ScriptDeclaration memory) {
        string memory built = string.concat("out/", name);
        if (!vm.exists(built)) revert ScriptNotBuilt(path);
        Vm.DirEntry[] memory artifacts = vm.readDir(built, 1);
        address found;
        ScriptDeclaration memory declared;
        for (uint256 index = 0; index < artifacts.length; index++) {
            string memory artifact = basename(artifacts[index].path);
            if (!endsWith(artifact, ".json")) continue;
            string memory contractId = string.concat(name, ":", stem(artifact, 5));
            if (vm.parseJsonBytes(vm.readFile(artifacts[index].path), ".bytecode.object").length == 0) continue;
            address instance = vm.deployCode(contractId);
            try IStoxScript(instance).declaration() returns (ScriptDeclaration memory candidate) {
                if (found != address(0)) revert ManyDeclarations(path);
                found = instance;
                declared = candidate;
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

    function networksJson(SupportedNetwork[] memory networks) internal returns (string memory json) {
        if (networks.length == 0) revert NoDeploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            string memory key = string.concat("networks.", vm.toString(networks[i].chainId));
            vm.serializeString(key, "network", networks[i].name);
            json = vm.serializeString(
                "networks",
                vm.toString(networks[i].chainId),
                vm.serializeAddress(key, "registry", LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            );
        }
    }

    /// @notice `migrations.json` for the scripts in `dir`.
    /// @param dir The directory.
    /// @return The JSON.
    function renderDir(string memory dir) public returns (string memory) {
        return renderFor(dir, LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks()));
    }

    /// @dev `migrations.json` for the scripts in `dir` on `networks`; reverts on no network.
    function renderFor(string memory dir, SupportedNetwork[] memory networks) internal returns (string memory) {
        (string[] memory paths, ScriptDeclaration[] memory declarations, address[] memory instances) = discover(dir);
        uint256 count = 0;
        for (uint256 i = 0; i < declarations.length; i++) {
            if (declarations[i].migration) count++;
        }
        string[] memory rows = new string[](count);
        uint256 row = 0;
        for (uint256 i = 0; i < declarations.length; i++) {
            if (!declarations[i].migration) continue;
            rows[row] = migrationJson(row, paths[i], declarations[i], instances[i], networks);
            row++;
        }
        vm.serializeUint("root", "version", 1);
        vm.serializeBytes32("root", "genesis", MIGRATION_HEAD_GENESIS);
        vm.serializeString("root", "networks", networksJson(networks));
        return vm.serializeString("root", "migrations", rows);
    }

    /// @notice Write the render of `dir` to `path`.
    /// @param dir The directory.
    /// @param path The file.
    function runTo(string memory dir, string memory path) public {
        vm.writeJson(renderDir(dir), path);
    }

    /// @notice Write `migrations.json`.
    function run() external {
        runTo(SCRIPTS, PATH);
    }
}
