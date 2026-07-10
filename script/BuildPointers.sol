// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {VmSafe} from "forge-std-1.16.1/src/Vm.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.0/src/lib/LibCodeGen.sol";
import {LibFs} from "rain-sol-codegen-0.1.0/src/lib/LibFs.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {StoxReceipt} from "../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../src/concrete/StoxReceiptVault.sol";
import {StoxCorporateActionsFacet} from "../src/concrete/StoxCorporateActionsFacet.sol";
import {StoxWrappedTokenVault} from "../src/concrete/StoxWrappedTokenVault.sol";
import {StoxUnifiedDeployer} from "../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {StoxWrappedTokenVaultBeacon} from "../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer
} from "../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {
    StoxOffchainAssetReceiptVaultBeaconSetDeployer
} from "../src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1
} from "../src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {ST0xOrchestrator} from "../src/concrete/ST0xOrchestrator.sol";
import {ST0xOrchestratorBeaconSetDeployer} from "../src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol";

contract BuildPointers is Script {
    /// @notice The canonical release tag. Read from `foundry.toml`
    /// `[package].version` — the single source of truth — with dots converted
    /// to underscores for the Solidity constant/dir form (`0.1.3` -> `0_1_3`).
    /// Everything version-dependent (the `<tag>/` snapshot dir, `DEPLOY_TAG`,
    /// the current-release aliases) derives from this.
    function deployTag() internal view returns (string memory) {
        string memory version = vm.parseTomlString(vm.readFile("foundry.toml"), ".package.version");
        bytes memory b = bytes(version);
        bytes memory out = new bytes(b.length);
        for (uint256 i = 0; i < b.length; i++) {
            out[i] = b[i] == "." ? bytes1("_") : b[i];
        }
        return string(out);
    }

    function addressConstantString(address addr) internal pure returns (string memory) {
        return string.concat(
            "\n",
            "/// @dev The deterministic deploy address of the contract when deployed via\n",
            "/// the Zoltu factory.\n",
            "address constant DEPLOYED_ADDRESS = address(",
            vm.toString(addr),
            ");\n"
        );
    }

    /// @notice Deploys a contract via the Zoltu factory and generates its
    /// pointer file containing `DEPLOYED_ADDRESS`, `CREATION_CODE`, and
    /// `RUNTIME_CODE` constants.
    /// @param name Must exactly match the contract's Solidity filename (without
    /// `.sol`), as it determines the generated pointer file path under
    /// `src/generated/<tag>/` — the frozen per-release snapshot for the current
    /// `deployTag()` (read from the canonical `foundry.toml` version). Historical
    /// tags are never regenerated; a release bump writes a new `<tag>/` snapshot
    /// beside them.
    /// @param creationCode The creation bytecode of the contract, typically
    /// obtained via `type(ContractName).creationCode`.
    function buildContractPointers(string memory name, bytes memory creationCode) internal {
        address deployed = LibRainDeploy.deployZoltu(creationCode);

        LibFs.buildFileForContract(
            vm,
            deployed,
            string.concat(deployTag(), "/", name),
            string.concat(
                addressConstantString(deployed),
                LibCodeGen.bytesConstantString(
                    vm, "/// @dev The creation bytecode of the contract.", "CREATION_CODE", creationCode
                ),
                LibCodeGen.bytesConstantString(
                    vm, "/// @dev The runtime bytecode of the contract.", "RUNTIME_CODE", deployed.code
                )
            )
        );
    }

    function run() external {
        LibRainDeploy.etchZoltuFactory(vm);

        // A fresh next-version slot has no `<tag>/` dir yet, and `vm.writeFile`
        // won't create one.
        vm.createDir(string.concat("src/generated/", deployTag()), true);

        buildContractPointers("StoxCorporateActionsFacet", type(StoxCorporateActionsFacet).creationCode);
        buildContractPointers("StoxReceipt", type(StoxReceipt).creationCode);
        buildContractPointers("StoxReceiptVault", type(StoxReceiptVault).creationCode);
        buildContractPointers("StoxWrappedTokenVault", type(StoxWrappedTokenVault).creationCode);
        // Beacon must be built before the deployer since the deployer imports
        // the beacon's pointer file.
        buildContractPointers("StoxWrappedTokenVaultBeacon", type(StoxWrappedTokenVaultBeacon).creationCode);
        buildContractPointers(
            "StoxWrappedTokenVaultBeaconSetDeployer", type(StoxWrappedTokenVaultBeaconSetDeployer).creationCode
        );
        // OARV deployer depends on StoxReceipt and StoxReceiptVault pointers.
        buildContractPointers(
            "StoxOffchainAssetReceiptVaultBeaconSetDeployer",
            type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode
        );
        buildContractPointers("StoxUnifiedDeployer", type(StoxUnifiedDeployer).creationCode);
        // Authorizers have no dependencies on other Stox contracts.
        buildContractPointers(
            "StoxOffchainAssetReceiptVaultAuthorizerV1", type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode
        );
        buildContractPointers(
            "StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1",
            type(StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1).creationCode
        );
        // ST0x orchestrator. The beacon-set deployer's constructor bakes the
        // orchestrator impl constant, so the impl must be built (and thus
        // Zoltu-deployed at that address) before the deployer.
        buildContractPointers("ST0xOrchestrator", type(ST0xOrchestrator).creationCode);
        buildContractPointers("ST0xOrchestratorBeaconSetDeployer", type(ST0xOrchestratorBeaconSetDeployer).creationCode);

        // Regenerate the deploy libs from the (now-updated) per-tag snapshots.
        genProdLibs();
    }

    // =========================================================================
    // Deploy-lib generation.
    //
    // Regenerates `src/generated/LibProdDeployV4.sol` (one versioned constant
    // set per release tag, each aliasing that tag's frozen `*.pointers.sol`
    // exports) and `src/generated/LibProdDeployCurrent.sol` (unversioned
    // aliases of the current `deployTag()`), from the per-tag snapshots on
    // disk. Emitted line-by-line via `vm.writeLine` so no single string grows
    // large enough to trip stack-too-deep (via_ir is off).
    // =========================================================================

    string constant GEN_V4_PATH = "src/generated/LibProdDeployV4.sol";
    string constant GEN_CURRENT_PATH = "src/generated/LibProdDeployCurrent.sol";
    string constant GEN_OWNER = "0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b";

    // REUSE-IgnoreStart  (the two SPDX lines below are the header EMITTED into
    // the generated files, not this script's own license — hide from reuse lint)
    string constant GEN_SPDX_LICENSE = "// SPDX-License-Identifier: LicenseRef-DCL-1.0";
    string constant GEN_SPDX_COPYRIGHT = "// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd";

    // REUSE-IgnoreEnd

    /// @notice Pointer filenames (without `.pointers.sol`) in a fixed order.
    function contractNames() internal pure returns (string[12] memory names) {
        names[0] = "StoxReceipt";
        names[1] = "StoxReceiptVault";
        names[2] = "StoxWrappedTokenVault";
        names[3] = "StoxUnifiedDeployer";
        names[4] = "StoxWrappedTokenVaultBeacon";
        names[5] = "StoxWrappedTokenVaultBeaconSetDeployer";
        names[6] = "StoxOffchainAssetReceiptVaultBeaconSetDeployer";
        names[7] = "StoxOffchainAssetReceiptVaultAuthorizerV1";
        names[8] = "StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1";
        names[9] = "StoxCorporateActionsFacet";
        names[10] = "ST0xOrchestrator";
        names[11] = "ST0xOrchestratorBeaconSetDeployer";
    }

    /// @notice The constant BASE for each contract, in the same order.
    function contractBases() internal pure returns (string[12] memory bases) {
        bases[0] = "STOX_RECEIPT";
        bases[1] = "STOX_RECEIPT_VAULT";
        bases[2] = "STOX_WRAPPED_TOKEN_VAULT";
        bases[3] = "STOX_UNIFIED_DEPLOYER";
        bases[4] = "STOX_WRAPPED_TOKEN_VAULT_BEACON";
        bases[5] = "STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER";
        bases[6] = "STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER";
        bases[7] = "STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1";
        bases[8] = "STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1";
        bases[9] = "STOX_CORPORATE_ACTIONS_FACET";
        bases[10] = "ST0X_ORCHESTRATOR";
        bases[11] = "ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER";
    }

    /// @notice The last path segment of `path` (the basename).
    function baseName(string memory path) internal pure returns (string memory) {
        bytes memory b = bytes(path);
        uint256 start = 0;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == "/") start = i + 1;
        }
        bytes memory out = new bytes(b.length - start);
        for (uint256 i = start; i < b.length; i++) {
            out[i - start] = b[i];
        }
        return string(out);
    }

    /// @notice True if `name` matches `\d+_\d+_\d+` (a release-tag dir name).
    function isTagName(string memory name) internal pure returns (bool) {
        bytes memory b = bytes(name);
        if (b.length == 0) return false;
        uint256 underscores = 0;
        bool prevDigit = false;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == "_") {
                if (!prevDigit) return false;
                underscores++;
                prevDigit = false;
            } else if (b[i] >= "0" && b[i] <= "9") {
                prevDigit = true;
            } else {
                return false;
            }
        }
        return underscores == 2 && prevDigit;
    }

    /// @notice A monotonic sort key for an `a_b_c` tag (each component < 1e6).
    function tagKey(string memory name) internal pure returns (uint256 key) {
        bytes memory b = bytes(name);
        uint256 num = 0;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == "_") {
                key = key * 1_000_000 + num;
                num = 0;
            } else {
                num = num * 10 + (uint8(b[i]) - 48);
            }
        }
        key = key * 1_000_000 + num;
    }

    /// @notice All release-tag dirs under `src/generated`, numeric-sorted
    /// (`readDir` order is unspecified, so an explicit sort keeps the
    /// generated output deterministic).
    function deployTags() internal returns (string[] memory tags) {
        VmSafe.DirEntry[] memory entries = vm.readDir("src/generated");
        string[] memory tmp = new string[](entries.length);
        uint256 n = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (!entries[i].isDir) continue;
            string memory name = baseName(entries[i].path);
            if (isTagName(name)) {
                tmp[n] = name;
                n++;
            }
        }
        tags = new string[](n);
        for (uint256 i = 0; i < n; i++) {
            tags[i] = tmp[i];
        }
        for (uint256 i = 1; i < n; i++) {
            string memory cur = tags[i];
            uint256 curKey = tagKey(cur);
            uint256 j = i;
            while (j > 0 && tagKey(tags[j - 1]) > curKey) {
                tags[j] = tags[j - 1];
                j--;
            }
            tags[j] = cur;
        }
    }

    function pointerExists(string memory tag, string memory name) internal returns (bool) {
        return vm.exists(string.concat("src/generated/", tag, "/", name, ".pointers.sol"));
    }

    function writeGeneratedHeader(string memory path) internal {
        vm.writeFile(path, "");
        vm.writeLine(path, GEN_SPDX_LICENSE);
        vm.writeLine(path, GEN_SPDX_COPYRIGHT);
        vm.writeLine(path, "pragma solidity ^0.8.25;");
        vm.writeLine(path, "");
        vm.writeLine(path, "// GENERATED by script/BuildPointers.sol. Do not edit.");
    }

    function v4ImportLine(string memory name, string memory base, string memory tag)
        internal
        pure
        returns (string memory)
    {
        string memory head =
            string.concat("import {DEPLOYED_ADDRESS as ", base, "_ADDRESS_", tag, "_GEN, BYTECODE_HASH as ", base);
        string memory mid = string.concat(
            "_CODEHASH_", tag, "_GEN, CREATION_CODE as ", base, "_CREATION_", tag, "_GEN, RUNTIME_CODE as ", base
        );
        string memory tail = string.concat("_RUNTIME_", tag, '_GEN} from "./', tag, "/", name, '.pointers.sol";');
        return string.concat(head, mid, tail);
    }

    /// @notice Emit the four aliased constants for one (tag, contract).
    function emitV4Constants(string memory tag, string memory base) internal {
        vm.writeLine(
            GEN_V4_PATH, string.concat("address constant ", base, "_", tag, " = ", base, "_ADDRESS_", tag, "_GEN;")
        );
        vm.writeLine(
            GEN_V4_PATH,
            string.concat("bytes32 constant ", base, "_CODEHASH_", tag, " = ", base, "_CODEHASH_", tag, "_GEN;")
        );
        vm.writeLine(
            GEN_V4_PATH,
            string.concat("bytes constant ", base, "_CREATION_CODE_", tag, " = ", base, "_CREATION_", tag, "_GEN;")
        );
        vm.writeLine(
            GEN_V4_PATH,
            string.concat("bytes constant ", base, "_RUNTIME_CODE_", tag, " = ", base, "_RUNTIME_", tag, "_GEN;")
        );
    }

    /// @notice Generate `LibProdDeployV4.sol`: one versioned alias set per tag.
    function genV4(string[] memory tags) internal {
        string[12] memory names = contractNames();
        string[12] memory bases = contractBases();

        writeGeneratedHeader(GEN_V4_PATH);
        for (uint256 t = 0; t < tags.length; t++) {
            for (uint256 c = 0; c < 12; c++) {
                if (pointerExists(tags[t], names[c])) {
                    vm.writeLine(GEN_V4_PATH, v4ImportLine(names[c], bases[c], tags[t]));
                }
            }
        }
        vm.writeLine(GEN_V4_PATH, "");
        vm.writeLine(GEN_V4_PATH, "library LibProdDeployV4 {");
        vm.writeLine(GEN_V4_PATH, string.concat("address constant BEACON_INITIAL_OWNER = address(", GEN_OWNER, ");"));
        vm.writeLine(GEN_V4_PATH, "address constant STOX_PROD_AUTHORISER_V4_CLONE = address(0);");
        vm.writeLine(
            GEN_V4_PATH,
            "bytes32 constant STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH ="
            " 0x2089950d3cc1112dd66a58adcfadeadc490b50053ac67be8bc676b4a2dcd1717;"
        );
        vm.writeLine(GEN_V4_PATH, "uint256 constant V4_SWAP_DEADLINE = 1_793_491_200;");
        for (uint256 t = 0; t < tags.length; t++) {
            for (uint256 c = 0; c < 12; c++) {
                if (pointerExists(tags[t], names[c])) {
                    emitV4Constants(tags[t], bases[c]);
                }
            }
        }
        vm.writeLine(GEN_V4_PATH, "}");
    }

    /// @notice Generate `LibProdDeployCurrent.sol`: unversioned aliases of the
    /// current release tag.
    function genCurrent() internal {
        string memory tag = deployTag();
        require(vm.exists(string.concat("src/generated/", tag)), "BuildPointers: current tag dir missing");
        string[12] memory names = contractNames();
        string[12] memory bases = contractBases();

        writeGeneratedHeader(GEN_CURRENT_PATH);
        vm.writeLine(GEN_CURRENT_PATH, 'import {LibProdDeployV4} from "./LibProdDeployV4.sol";');
        vm.writeLine(GEN_CURRENT_PATH, "");
        vm.writeLine(GEN_CURRENT_PATH, "library LibProdDeployCurrent {");
        vm.writeLine(GEN_CURRENT_PATH, string.concat('string constant DEPLOY_TAG = "', tag, '";'));
        vm.writeLine(GEN_CURRENT_PATH, "address constant BEACON_INITIAL_OWNER = LibProdDeployV4.BEACON_INITIAL_OWNER;");
        vm.writeLine(
            GEN_CURRENT_PATH,
            "address constant STOX_PROD_AUTHORISER_V4_CLONE = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;"
        );
        vm.writeLine(
            GEN_CURRENT_PATH,
            "bytes32 constant STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH;"
        );
        for (uint256 c = 0; c < 12; c++) {
            if (!pointerExists(tag, names[c])) continue;
            string memory base = bases[c];
            vm.writeLine(
                GEN_CURRENT_PATH, string.concat("address constant ", base, " = LibProdDeployV4.", base, "_", tag, ";")
            );
            vm.writeLine(
                GEN_CURRENT_PATH,
                string.concat("bytes32 constant ", base, "_CODEHASH = LibProdDeployV4.", base, "_CODEHASH_", tag, ";")
            );
        }
        vm.writeLine(GEN_CURRENT_PATH, "}");
    }

    function genProdLibs() internal {
        string[] memory tags = deployTags();
        genV4(tags);
        genCurrent();
    }
}
