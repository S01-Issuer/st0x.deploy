// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript} from "rain-deploy-0.1.11/src/abstract/BuildScript.sol";
import {LibRainDeploySnapshot} from "rain-deploy-0.1.11/src/lib/LibRainDeploySnapshot.sol";
import {DeployCandidate} from "../src/abstract/RainDeploySuitesBase.sol";
import {StoxDeploySuites} from "../src/abstract/StoxDeploySuites.sol";

/// One contract's generated files: its rolling snapshot, its released-suites
/// lib, and its constants in `LibProdDeployV4` / `LibProdDeployCurrent`.
struct GeneratedContract {
    /// Names the snapshot inside `src/generated/<dir>/` and the released-suites
    /// lib.
    string contractName;
    /// The `LibProdDeployV4` / `LibProdDeployCurrent` constant base, e.g.
    /// `STOX_RECEIPT`.
    string constantBase;
    /// Snapshots are written from its `sourceCreationCode` and
    /// `snapshot.dependencies`; the released lib takes its suite key and
    /// artifact path from its `snapshot`.
    DeployCandidate candidate;
}

/// @title Build
/// @notice Generates the deploy pins for every contract this repo deploys.
/// `run()` and `cutRelease()` are inherited from `BuildScript`.
///
/// Beside the released-suites libs `rain-deploy` emits, this regenerates
/// `src/generated/LibProdDeployV4.sol` (one aliased constant set per frozen
/// release and one for `candidate`) and `src/generated/LibProdDeployCurrent.sol`
/// (unversioned aliases of `candidate`), which are this repo's consumer API.
contract Build is BuildScript, StoxDeploySuites {
    string constant GEN_V4_PATH = "src/generated/LibProdDeployV4.sol";
    string constant GEN_CURRENT_PATH = "src/generated/LibProdDeployCurrent.sol";
    string constant GEN_OWNER = "0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b";

    // REUSE-IgnoreStart  (the two SPDX lines below are the header EMITTED into
    // the generated files, not this script's own license — hide from reuse lint)
    string constant GEN_SPDX_LICENSE = "// SPDX-License-Identifier: LicenseRef-DCL-1.0";
    string constant GEN_SPDX_COPYRIGHT = "// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd";

    // REUSE-IgnoreEnd

    /// Every contract this repo generates deploy pins for, in the order the
    /// candidates are declared: each one's dependencies are snapshotted, and
    /// therefore Zoltu deployed in the build, before it.
    /// @return The generated contracts.
    function generatedContracts() internal pure returns (GeneratedContract[] memory) {
        GeneratedContract[] memory contracts = new GeneratedContract[](12);
        contracts[0] = GeneratedContract("StoxCorporateActionsFacet", "STOX_CORPORATE_ACTIONS_FACET", facetCandidate());
        contracts[1] = GeneratedContract("StoxReceipt", "STOX_RECEIPT", receiptCandidate());
        contracts[2] = GeneratedContract("StoxReceiptVault", "STOX_RECEIPT_VAULT", receiptVaultCandidate());
        contracts[3] = GeneratedContract("StoxWrappedTokenVault", "STOX_WRAPPED_TOKEN_VAULT", wrappedVaultCandidate());
        contracts[4] = GeneratedContract(
            "StoxWrappedTokenVaultBeacon", "STOX_WRAPPED_TOKEN_VAULT_BEACON", wrappedBeaconCandidate()
        );
        contracts[5] = GeneratedContract(
            "StoxWrappedTokenVaultBeaconSetDeployer",
            "STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER",
            wrappedSetDeployerCandidate()
        );
        contracts[6] = GeneratedContract(
            "StoxOffchainAssetReceiptVaultBeaconSetDeployer",
            "STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER",
            oarvSetDeployerCandidate()
        );
        contracts[7] = GeneratedContract("StoxUnifiedDeployer", "STOX_UNIFIED_DEPLOYER", unifiedDeployerCandidate());
        contracts[8] = GeneratedContract(
            "StoxOffchainAssetReceiptVaultAuthorizerV1",
            "STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1",
            authorizerCandidate()
        );
        contracts[9] = GeneratedContract(
            "StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1",
            "STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1",
            paymentMintAuthorizerCandidate()
        );
        contracts[10] = GeneratedContract("ST0xOrchestrator", "ST0X_ORCHESTRATOR", orchestratorCandidate());
        contracts[11] = GeneratedContract(
            "ST0xOrchestratorBeaconSetDeployer",
            "ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER",
            orchestratorSetDeployerCandidate()
        );
        return contracts;
    }

    /// @inheritdoc BuildScript
    function snapshotContractNames() internal pure override returns (string[] memory) {
        GeneratedContract[] memory contracts = generatedContracts();
        string[] memory names = new string[](contracts.length);
        for (uint256 i = 0; i < contracts.length; i++) {
            names[i] = contracts[i].contractName;
        }
        return names;
    }

    /// @inheritdoc BuildScript
    function regenerateSnapshots() internal override {
        GeneratedContract[] memory contracts = generatedContracts();
        for (uint256 i = 0; i < contracts.length; i++) {
            LibRainDeploySnapshot.writeSnapshot(
                vm,
                recordRoot(),
                LibRainDeploySnapshot.CANDIDATE,
                contracts[i].contractName,
                contracts[i].candidate.sourceCreationCode,
                contracts[i].candidate.snapshot.dependencies
            );
        }
    }

    /// @inheritdoc BuildScript
    /// @dev Every released-suites lib, the aggregate over them, then
    /// `LibProdDeployV4` and `LibProdDeployCurrent`.
    function regenerateLibs() internal override {
        GeneratedContract[] memory contracts = generatedContracts();
        string[] memory names = new string[](contracts.length);
        string[] memory bases = new string[](contracts.length);
        for (uint256 i = 0; i < contracts.length; i++) {
            LibRainDeploySnapshot.writeReleasedSuitesLib(
                vm,
                LibRainDeploySnapshot.LIB_DIR,
                recordRoot(),
                contracts[i].contractName,
                contracts[i].candidate.snapshot
            );
            names[i] = contracts[i].contractName;
            bases[i] = contracts[i].constantBase;
        }
        LibRainDeploySnapshot.writeReleasedSuitesAggregate(vm, LibRainDeploySnapshot.LIB_DIR, names);

        genV4(names, bases, releaseTags());
        genCurrent(bases);
    }

    // =========================================================================
    // `LibProdDeployV4` / `LibProdDeployCurrent` generation. Emitted
    // line-by-line via `vm.writeLine` so no single string grows large enough to
    // trip stack-too-deep (via_ir is off).
    // =========================================================================

    /// Every frozen release tag in the record, in release order, followed by
    /// `candidate`.
    /// @return tags The tags.
    function releaseTags() internal view returns (string[] memory tags) {
        string[] memory paths = LibRainDeploySnapshot.frozenSnapshotPaths(vm, recordRoot());
        string[] memory found = new string[](paths.length);
        uint256 n = 0;
        for (uint256 i = 0; i < paths.length; i++) {
            string memory tag = LibRainDeploySnapshot.tagForRecordPath(vm, paths[i]);
            bool seen = false;
            for (uint256 j = 0; j < n; j++) {
                if (keccak256(bytes(found[j])) == keccak256(bytes(tag))) {
                    seen = true;
                    break;
                }
            }
            if (!seen) {
                // Insertion into release order.
                uint256 k = n;
                while (k > 0 && LibRainDeploySnapshot.tagPrecedes(vm, tag, found[k - 1])) {
                    found[k] = found[k - 1];
                    k--;
                }
                found[k] = tag;
                n++;
            }
        }
        tags = new string[](n + 1);
        for (uint256 i = 0; i < n; i++) {
            tags[i] = found[i];
        }
        tags[n] = LibRainDeploySnapshot.CANDIDATE;
    }

    /// The constant-name suffix for a tag dir. Release tags are used verbatim
    /// (`0_1_1`); `candidate` becomes `CANDIDATE`.
    /// @param tag The tag.
    /// @return The suffix.
    function tagSuffix(string memory tag) internal pure returns (string memory) {
        if (keccak256(bytes(tag)) == keccak256(bytes(LibRainDeploySnapshot.CANDIDATE))) return "CANDIDATE";
        return tag;
    }

    /// The file a tag holds for a contract, if any. Releases frozen before this
    /// repo built on `rain-deploy` hold `<Contract>.pointers.sol`; everything
    /// since, `candidate` included, holds `<Contract>.sol`.
    /// @param tag The tag.
    /// @param name The contract name.
    /// @return file The file name within the tag dir, empty if there is none.
    function snapshotFile(string memory tag, string memory name) internal view returns (string memory file) {
        string memory dir = string.concat(recordRoot(), "/", tag, "/");
        string memory legacy = string.concat(name, ".pointers.sol");
        if (vm.exists(string.concat(dir, legacy))) return legacy;
        string memory current = string.concat(name, ".sol");
        if (vm.exists(string.concat(dir, current))) return current;
        return "";
    }

    function writeGeneratedHeader(string memory path) internal {
        vm.writeFile(path, "");
        vm.writeLine(path, GEN_SPDX_LICENSE);
        vm.writeLine(path, GEN_SPDX_COPYRIGHT);
        vm.writeLine(path, "pragma solidity ^0.8.25;");
        vm.writeLine(path, "");
        vm.writeLine(path, "// GENERATED by script/Build.sol. Do not edit.");
    }

    function v4ImportLine(string memory file, string memory base, string memory tag)
        internal
        pure
        returns (string memory)
    {
        string memory suffix = tagSuffix(tag);
        string memory head =
            string.concat("import {DEPLOYED_ADDRESS as ", base, "_ADDRESS_", suffix, "_GEN, BYTECODE_HASH as ", base);
        string memory mid = string.concat(
            "_CODEHASH_", suffix, "_GEN, CREATION_CODE as ", base, "_CREATION_", suffix, "_GEN, RUNTIME_CODE as ", base
        );
        string memory tail = string.concat("_RUNTIME_", suffix, '_GEN} from "./', tag, "/", file, '";');
        return string.concat(head, mid, tail);
    }

    /// Emit the four aliased constants for one (tag, contract).
    function emitV4Constants(string memory tag, string memory base) internal {
        string memory suffix = tagSuffix(tag);
        vm.writeLine(
            GEN_V4_PATH,
            string.concat("address constant ", base, "_", suffix, " = ", base, "_ADDRESS_", suffix, "_GEN;")
        );
        vm.writeLine(
            GEN_V4_PATH,
            string.concat("bytes32 constant ", base, "_CODEHASH_", suffix, " = ", base, "_CODEHASH_", suffix, "_GEN;")
        );
        vm.writeLine(
            GEN_V4_PATH,
            string.concat(
                "bytes constant ", base, "_CREATION_CODE_", suffix, " = ", base, "_CREATION_", suffix, "_GEN;"
            )
        );
        vm.writeLine(
            GEN_V4_PATH,
            string.concat("bytes constant ", base, "_RUNTIME_CODE_", suffix, " = ", base, "_RUNTIME_", suffix, "_GEN;")
        );
    }

    /// Generate `LibProdDeployV4.sol`: one versioned alias set per tag.
    function genV4(string[] memory names, string[] memory bases, string[] memory tags) internal {
        writeGeneratedHeader(GEN_V4_PATH);
        for (uint256 t = 0; t < tags.length; t++) {
            for (uint256 c = 0; c < names.length; c++) {
                string memory file = snapshotFile(tags[t], names[c]);
                if (bytes(file).length > 0) {
                    vm.writeLine(GEN_V4_PATH, v4ImportLine(file, bases[c], tags[t]));
                }
            }
        }
        vm.writeLine(GEN_V4_PATH, "");
        vm.writeLine(GEN_V4_PATH, "library LibProdDeployV4 {");
        vm.writeLine(GEN_V4_PATH, string.concat("address constant BEACON_INITIAL_OWNER = address(", GEN_OWNER, ");"));
        vm.writeLine(
            GEN_V4_PATH,
            "address constant STOX_PROD_AUTHORISER_V4_CLONE =" " address(0x315b16faa6eE413faBCa877d3851B3818369f0cD);"
        );
        vm.writeLine(
            GEN_V4_PATH,
            "bytes32 constant STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH ="
            " 0x2089950d3cc1112dd66a58adcfadeadc490b50053ac67be8bc676b4a2dcd1717;"
        );
        // Ethereum V4 authoriser clone — a nonce-based `CloneFactory.clone`
        // deploy like Base's, so its address is not derivable and is carried
        // here as a literal. Shares the EIP-1167 codehash above: both chains'
        // clones embed the same authoriser impl, so both hash identically.
        //
        // The address is NOT chain-unique — a different clone occupies it on
        // Base — so a consumer must match the codehash, not merely find code.
        vm.writeLine(
            GEN_V4_PATH,
            "address constant STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM = address(0x66566cc91dEAf818859bD4b09B7903ac48998157);"
        );
        vm.writeLine(
            GEN_V4_PATH,
            "address constant STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM = address(0x66566cc91dEAf818859bD4b09B7903ac48998157);"
        );
        // Robinhood Chain and BNB Smart Chain V4 authoriser clones: the logged
        // addresses of the `20260619-deploy-v4-authoriser-clone` broadcasts.
        // `CloneFactory.clone` is a plain CREATE, so the address is a function
        // of the factory and its nonce alone; each chain's first clone from its
        // fresh factory (nonce 1) lands at the Ethereum / HyperEVM address. The
        // impl plays no part, which is why Base, same impl and factory, differs.
        vm.writeLine(
            GEN_V4_PATH,
            "address constant STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD = address(0x66566cc91dEAf818859bD4b09B7903ac48998157);"
        );
        vm.writeLine(
            GEN_V4_PATH,
            "address constant STOX_PROD_AUTHORISER_V4_CLONE_BSC = address(0x66566cc91dEAf818859bD4b09B7903ac48998157);"
        );
        vm.writeLine(GEN_V4_PATH, "uint256 constant V4_SWAP_DEADLINE = 1_793_491_200;");
        // ST0x orchestrator beacon + production instance — CREATE-derived
        // from the 0.1.30 orchestrator beacon-set deployer (itself a Zoltu
        // deploy), so chain-invariant like every Zoltu pin: the beacon is the
        // deployer constructor's CREATE at account nonce 1, and the instance
        // is the first `deploy()` call's BeaconProxy at nonce 2
        // (`20260818-deploy-orchestrator` refuses any other deployer state).
        // Carried as literals like the authoriser clone above;
        // `testOrchestratorBeaconPin` / `testOrchestratorInstancePin`
        // re-derive both from the deployer pin so a drifted literal fails a
        // test.
        vm.writeLine(
            GEN_V4_PATH,
            "address constant ST0X_ORCHESTRATOR_BEACON = address(0xb9DCd744b0413Dff0EDC70A5B229c7aa03734613);"
        );
        vm.writeLine(
            GEN_V4_PATH,
            "address constant ST0X_ORCHESTRATOR_INSTANCE = address(0x3A7387a484d87Aa8bBA45E98AAB401Ce4FBF03E2);"
        );
        for (uint256 t = 0; t < tags.length; t++) {
            for (uint256 c = 0; c < names.length; c++) {
                if (bytes(snapshotFile(tags[t], names[c])).length > 0) {
                    emitV4Constants(tags[t], bases[c]);
                }
            }
        }
        vm.writeLine(GEN_V4_PATH, "}");
    }

    /// Generate `LibProdDeployCurrent.sol`: unversioned aliases of `candidate`,
    /// which `regenerateSnapshots` has just written for every contract.
    function genCurrent(string[] memory bases) internal {
        string memory tag = LibRainDeploySnapshot.CANDIDATE;
        string memory suffix = tagSuffix(tag);

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
        for (uint256 c = 0; c < bases.length; c++) {
            string memory base = bases[c];
            vm.writeLine(
                GEN_CURRENT_PATH,
                string.concat("address constant ", base, " = LibProdDeployV4.", base, "_", suffix, ";")
            );
            vm.writeLine(
                GEN_CURRENT_PATH,
                string.concat(
                    "bytes32 constant ", base, "_CODEHASH = LibProdDeployV4.", base, "_CODEHASH_", suffix, ";"
                )
            );
        }
        vm.writeLine(GEN_CURRENT_PATH, "}");
    }
}
