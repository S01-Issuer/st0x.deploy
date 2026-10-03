// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {VmSafe} from "forge-std-1.16.2/src/Vm.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.37/src/lib/LibCodeGen.sol";
import {LibFs, GENERATED_DIR} from "rain-sol-codegen-0.1.37/src/lib/LibFs.sol";
import {LibGenParseMeta} from "rainlang-interface-0.2.9/src/lib/codegen/LibGenParseMeta.sol";
import {BuildScript} from "rain-deploy-0.1.10/src/abstract/BuildScript.sol";
import {LibRainDeploy} from "rain-deploy-0.1.10/src/lib/LibRainDeploy.sol";
import {LibRainDeploySnapshot} from "rain-deploy-0.1.10/src/lib/LibRainDeploySnapshot.sol";
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
import {St0xAttestSubParser} from "../src/concrete/St0xAttestSubParser.sol";
import {LibSt0xAttestSubParser, PARSE_META_BUILD_DEPTH} from "../src/lib/LibSt0xAttestSubParser.sol";
import {LibProdDeployCurrent} from "../src/generated/LibProdDeployCurrent.sol";

contract BuildPointers is BuildScript {
    /// @notice How many contracts `contractNames()` / `contractBases()`
    /// enumerate: every candidate-snapshot contract the deploy libs alias.
    uint256 constant CONTRACT_COUNT = 13;

    /// @notice The rolling "current source" snapshot tag — always `candidate`,
    /// never a version number. `src/generated/candidate/` is regenerated from
    /// the current source on every run; a numbered snapshot is frozen only when
    /// a release tag promotes `candidate` (see `script/cut-release.sh`). Source
    /// self-references (`LibProdDeployCurrent`) always resolve to `candidate`,
    /// so they track whatever the source currently compiles to, while numbered
    /// snapshots (`0_1_1`, …) stay frozen and are never regenerated here.
    string constant CANDIDATE_TAG = "candidate";

    function deployTag() internal pure returns (string memory) {
        return CANDIDATE_TAG;
    }

    /// @notice The constant-name suffix for a tag dir. Numbered tags use the tag
    /// verbatim (`0_1_1`); the rolling `candidate` dir uses `CANDIDATE`, so its
    /// generated constants read `STOX_RECEIPT_CANDIDATE` rather than the
    /// lowercase dir name.
    function tagSuffix(string memory tag) internal pure returns (string memory) {
        if (keccak256(bytes(tag)) == keccak256(bytes(CANDIDATE_TAG))) return "CANDIDATE";
        return tag;
    }

    /// @notice Deploys a contract via the Zoltu factory and generates its
    /// pointer file containing `DEPLOYED_ADDRESS`, `CREATION_CODE`, and
    /// `RUNTIME_CODE` constants.
    /// @param name Must exactly match the contract's Solidity filename (without
    /// `.sol`), as it determines the generated pointer file path under
    /// `src/generated/<tag>/` — the rolling `candidate` snapshot for the
    /// current `deployTag()`. Numbered release snapshots are frozen and never
    /// regenerated here; a release freezes a copy of `candidate` beside them
    /// (see `script/cut-release.sh`).
    /// @param creationCode The creation bytecode of the contract, typically
    /// obtained via `type(ContractName).creationCode`.
    /// @return deployed The Zoltu address the contract was deployed to, for a
    /// caller that reads pointer tables back off the live instance.
    function buildContractPointers(string memory name, bytes memory creationCode) internal returns (address deployed) {
        LibRainDeploySnapshot.writeSnapshot(vm, deployTag(), name, creationCode, snapshotDependencies(name));
        // `writeSnapshot` has already Zoltu-deployed this creation code, and it
        // returns the path it wrote rather than the address. Derive the address
        // instead of deploying again: `deployZoltu` reverts `DeployFailed` on an
        // address that already holds code, so a second call is not a no-op.
        deployed = LibRainDeploy.zoltuAddress(creationCode);
    }

    /// @notice The addresses that MUST already carry code on a network before
    /// `name` can be broadcast there, recorded into its snapshot.
    ///
    /// Read off the constructors rather than assumed: the beacon-set deployers
    /// bake their implementation's address at construction and the unified
    /// deployer bakes the two beacon-set deployers, so broadcasting one onto a
    /// network whose prerequisite is absent produces a deployer whose `deploy()`
    /// cannot work. An empty list is a claim that nothing must pre-exist, so it
    /// is only correct for the contracts that genuinely bake nothing — the
    /// implementations, the beacon, the authorizers, the facet and the
    /// subparser.
    ///
    /// The addresses come from `LibProdDeployCurrent`, which is the same
    /// generated source the constructors read, so a dependency recorded here
    /// and the address actually baked cannot diverge.
    /// @param name The contract whose snapshot is being written.
    /// @return The dependency addresses.
    function snapshotDependencies(string memory name) internal pure returns (address[] memory) {
        bytes32 key = keccak256(bytes(name));

        if (key == keccak256("ST0xOrchestratorBeaconSetDeployer")) {
            address[] memory deps = new address[](1);
            deps[0] = LibProdDeployCurrent.ST0X_ORCHESTRATOR;
            return deps;
        }
        if (key == keccak256("StoxWrappedTokenVaultBeaconSetDeployer")) {
            address[] memory deps = new address[](1);
            deps[0] = LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT_BEACON;
            return deps;
        }
        if (key == keccak256("StoxOffchainAssetReceiptVaultBeaconSetDeployer")) {
            address[] memory deps = new address[](2);
            deps[0] = LibProdDeployCurrent.STOX_RECEIPT;
            deps[1] = LibProdDeployCurrent.STOX_RECEIPT_VAULT;
            return deps;
        }
        if (key == keccak256("StoxUnifiedDeployer")) {
            address[] memory deps = new address[](2);
            deps[0] = LibProdDeployCurrent.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER;
            deps[1] = LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER;
            return deps;
        }
        return new address[](0);
    }

    /// @inheritdoc BuildScript
    /// @dev In declaration order, which is also build order: a deployer bakes
    /// its implementation's address, so the implementation has to have been
    /// Zoltu-deployed before the deployer's creation code is read.
    function snapshotContractNames() internal pure override returns (string[] memory) {
        string[CONTRACT_COUNT] memory fixedNames = contractNames();
        string[] memory names = new string[](CONTRACT_COUNT);
        for (uint256 i = 0; i < CONTRACT_COUNT; i++) {
            names[i] = fixedNames[i];
        }
        return names;
    }

    /// @inheritdoc BuildScript
    function regenerateLibs() internal override {
        genProdLibs();
    }

    /// @inheritdoc BuildScript
    function regenerateSnapshots() internal override {
        LibRainDeploy.etchZoltuFactory(vm);

        // Regenerate the rolling `candidate/` snapshot from current source.
        // `vm.writeFile` won't create the dir, so ensure it exists first.
        vm.createDir(LibFs.dirForTag(deployTag()), true);

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
        // The Rainlang subparser. Its parse meta and function pointer tables
        // are read back off the instance just deployed, so the candidate
        // snapshot and the tables come from one build of the same source.
        buildSubParserPointers(buildContractPointers("St0xAttestSubParser", type(St0xAttestSubParser).creationCode));
    }

    /// @notice Generates `src/generated/St0xAttestSubParserPointers.sol`: the
    /// described-by meta hash, the parse meta, and the word parser, operand
    /// handler and literal parser pointer tables, read back off the deployed
    /// subparser. `St0xAttestSubParser` imports that file, so its creation
    /// code embeds the tables and the candidate snapshot converges on the
    /// second run after a table changes. Run `script/build-meta.sh` first so
    /// the meta hash is of the current words.
    /// @param subParser The subparser `buildContractPointers` deployed.
    function buildSubParserPointers(address subParser) internal {
        LibFs.buildFileForContract(
            vm,
            subParser,
            "St0xAttestSubParserPointers",
            string.concat(
                LibCodeGen.describedByMetaHashConstantString(vm, "St0xAttestSubParser"),
                LibGenParseMeta.parseMetaConstantString(
                    vm, LibSt0xAttestSubParser.authoringMetaV2(), PARSE_META_BUILD_DEPTH
                ),
                LibCodeGen.subParserWordParsersConstantString(vm, St0xAttestSubParser(subParser)),
                LibCodeGen.operandHandlerFunctionPointersConstantString(vm, St0xAttestSubParser(subParser)),
                LibCodeGen.literalParserFunctionPointersConstantString(vm, St0xAttestSubParser(subParser))
            )
        );
    }

    // =========================================================================
    // Deploy-lib generation.
    //
    // Regenerates `src/generated/LibProdDeployV4.sol` (one versioned constant
    // set per release tag, each aliasing that tag's frozen `*.sol`
    // exports) and `src/generated/LibProdDeployCurrent.sol` (unversioned
    // aliases of the current `deployTag()`), from the per-tag snapshots on
    // disk. Emitted line-by-line via `vm.writeLine` so no single string grows
    // large enough to trip stack-too-deep (via_ir is off).
    // =========================================================================

    /// @notice The aggregate deploy lib's path, from `LibFs.pathForContract`
    /// rather than spelled here.
    ///
    /// Functions rather than `constant`s because a `constant` cannot be
    /// initialised from a function call, and the definition living in `LibFs`
    /// is worth more than the storage-free spelling: these are the same
    /// `GENERATED_DIR` the per-tag snapshots are written under, so a repo that
    /// spelled them separately would have two places to move.
    /// @return The path of `LibProdDeployV4.sol`.
    function genV4Path() internal pure returns (string memory) {
        return LibFs.pathForContract("LibProdDeployV4");
    }

    /// @notice The current-tag alias lib's path, on the same basis as
    /// `genV4Path`.
    /// @return The path of `LibProdDeployCurrent.sol`.
    function genCurrentPath() internal pure returns (string memory) {
        return LibFs.pathForContract("LibProdDeployCurrent");
    }
    string constant GEN_OWNER = "0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b";

    // REUSE-IgnoreStart  (the two SPDX lines below are the header EMITTED into
    // the generated files, not this script's own license — hide from reuse lint)
    string constant GEN_SPDX_LICENSE = "// SPDX-License-Identifier: LicenseRef-DCL-1.0";
    string constant GEN_SPDX_COPYRIGHT = "// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd";

    // REUSE-IgnoreEnd

    /// @notice Pointer filenames (without `.sol`) in a fixed order.
    function contractNames() internal pure returns (string[CONTRACT_COUNT] memory names) {
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
        names[12] = "St0xAttestSubParser";
    }

    /// @notice The constant BASE for each contract, in the same order.
    function contractBases() internal pure returns (string[CONTRACT_COUNT] memory bases) {
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
        bases[12] = "ST0X_ATTEST_SUB_PARSER";
    }

    /// @notice True if `name` matches `\d+_\d+_\d+` (a release-tag dir name).
    /// @notice True when `a` is a release tag that precedes release tag `b`.
    ///
    /// `LibRainDeploySnapshot.tagPrecedes` is the ordering, so a tag orders
    /// here exactly as it does where a release is cut; this only adds where
    /// `candidate` sits, which that function cannot answer because it parses
    /// each component as a number. `candidate` is the rolling head and sorts
    /// after every frozen tag, so it is never the lesser side of a comparison
    /// and two candidates never meet.
    /// @param a The left tag.
    /// @param b The right tag.
    /// @return True when `a` precedes `b`.
    function tagPrecedes(string memory a, string memory b) internal view returns (bool) {
        if (keccak256(bytes(a)) == keccak256(bytes(CANDIDATE_TAG))) {
            return false;
        }
        if (keccak256(bytes(b)) == keccak256(bytes(CANDIDATE_TAG))) {
            return true;
        }
        return LibRainDeploySnapshot.tagPrecedes(vm, a, b);
    }

    /// @notice All release-tag dirs under `src/generated`, numeric-sorted
    /// (`readDir` order is unspecified, so an explicit sort keeps the
    /// generated output deterministic).
    function deployTags() internal view returns (string[] memory tags) {
        VmSafe.DirEntry[] memory entries = vm.readDir(GENERATED_DIR);
        string[] memory tmp = new string[](entries.length);
        uint256 n = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (!entries[i].isDir) continue;
            string memory name = LibFs.lastPathSegment(entries[i].path);
            if (LibRainDeploySnapshot.isTag(name) || keccak256(bytes(name)) == keccak256(bytes(CANDIDATE_TAG))) {
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
            uint256 j = i;
            while (j > 0 && tagPrecedes(cur, tags[j - 1])) {
                tags[j] = tags[j - 1];
                j--;
            }
            tags[j] = cur;
        }
    }

    /// @notice The path a snapshot of `name` has inside `tag`.
    ///
    /// `LibFs.pathForTaggedContract` is where this is defined, and
    /// `rain-deploy`'s `pathForSnapshot` delegates to that same function rather
    /// than concatenating its own, so that the path a release is frozen FROM is
    /// the one `LibFs` wrote TO. There is one spelling, `<Name>.sol`, for every
    /// tag including the frozen ones.
    /// @param tag The snapshot directory.
    /// @param name The contract name.
    /// @return The path.
    function pointerPath(string memory tag, string memory name) internal pure returns (string memory) {
        return LibFs.pathForTaggedContract(tag, name);
    }

    /// @notice The file name, rather than the path, of that same snapshot — the
    /// form a generated import line needs.
    /// @param tag The snapshot directory.
    /// @param name The contract name.
    /// @return The final path segment.
    function pointerFileName(string memory tag, string memory name) internal pure returns (string memory) {
        return LibFs.lastPathSegment(pointerPath(tag, name));
    }

    function pointerExists(string memory tag, string memory name) internal view returns (bool) {
        return vm.exists(pointerPath(tag, name));
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
        view
        returns (string memory)
    {
        string memory suffix = tagSuffix(tag);
        string memory head =
            string.concat("import {DEPLOYED_ADDRESS as ", base, "_ADDRESS_", suffix, "_GEN, BYTECODE_HASH as ", base);
        string memory mid = string.concat(
            "_CODEHASH_", suffix, "_GEN, CREATION_CODE as ", base, "_CREATION_", suffix, "_GEN, RUNTIME_CODE as ", base
        );
        string memory tail =
            string.concat("_RUNTIME_", suffix, '_GEN} from "./', tag, "/", pointerFileName(tag, name), '";');
        return string.concat(head, mid, tail);
    }

    /// @notice Emit the four aliased constants for one (tag, contract).
    function emitV4Constants(string memory tag, string memory base) internal {
        string memory suffix = tagSuffix(tag);
        vm.writeLine(
            genV4Path(),
            string.concat("address constant ", base, "_", suffix, " = ", base, "_ADDRESS_", suffix, "_GEN;")
        );
        vm.writeLine(
            genV4Path(),
            string.concat("bytes32 constant ", base, "_CODEHASH_", suffix, " = ", base, "_CODEHASH_", suffix, "_GEN;")
        );
        vm.writeLine(
            genV4Path(),
            string.concat(
                "bytes constant ", base, "_CREATION_CODE_", suffix, " = ", base, "_CREATION_", suffix, "_GEN;"
            )
        );
        vm.writeLine(
            genV4Path(),
            string.concat("bytes constant ", base, "_RUNTIME_CODE_", suffix, " = ", base, "_RUNTIME_", suffix, "_GEN;")
        );
    }

    /// @notice Generate `LibProdDeployV4.sol`: one versioned alias set per tag.
    function genV4(string[] memory tags) internal {
        string[CONTRACT_COUNT] memory names = contractNames();
        string[CONTRACT_COUNT] memory bases = contractBases();

        writeGeneratedHeader(genV4Path());
        for (uint256 t = 0; t < tags.length; t++) {
            for (uint256 c = 0; c < CONTRACT_COUNT; c++) {
                if (pointerExists(tags[t], names[c])) {
                    vm.writeLine(genV4Path(), v4ImportLine(names[c], bases[c], tags[t]));
                }
            }
        }
        vm.writeLine(genV4Path(), "");
        vm.writeLine(genV4Path(), "library LibProdDeployV4 {");
        vm.writeLine(genV4Path(), string.concat("address constant BEACON_INITIAL_OWNER = address(", GEN_OWNER, ");"));
        vm.writeLine(
            genV4Path(),
            "address constant STOX_PROD_AUTHORISER_V4_CLONE =" " address(0x315b16faa6eE413faBCa877d3851B3818369f0cD);"
        );
        vm.writeLine(
            genV4Path(),
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
            genV4Path(),
            "address constant STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM = address(0x66566cc91dEAf818859bD4b09B7903ac48998157);"
        );
        vm.writeLine(
            genV4Path(),
            "address constant STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM = address(0x66566cc91dEAf818859bD4b09B7903ac48998157);"
        );
        // Robinhood Chain and BNB Smart Chain V4 authoriser clones: the logged
        // addresses of the `20260619-deploy-v4-authoriser-clone` broadcasts.
        // `CloneFactory.clone` is a plain CREATE, so the address is a function
        // of the factory and its nonce alone; each chain's first clone from its
        // fresh factory (nonce 1) lands at the Ethereum / HyperEVM address. The
        // impl plays no part, which is why Base, same impl and factory, differs.
        vm.writeLine(
            genV4Path(),
            "address constant STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD = address(0x66566cc91dEAf818859bD4b09B7903ac48998157);"
        );
        vm.writeLine(
            genV4Path(),
            "address constant STOX_PROD_AUTHORISER_V4_CLONE_BSC = address(0x66566cc91dEAf818859bD4b09B7903ac48998157);"
        );
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
            genV4Path(),
            "address constant ST0X_ORCHESTRATOR_BEACON = address(0xb9DCd744b0413Dff0EDC70A5B229c7aa03734613);"
        );
        vm.writeLine(
            genV4Path(),
            "address constant ST0X_ORCHESTRATOR_INSTANCE = address(0x3A7387a484d87Aa8bBA45E98AAB401Ce4FBF03E2);"
        );
        for (uint256 t = 0; t < tags.length; t++) {
            for (uint256 c = 0; c < CONTRACT_COUNT; c++) {
                if (pointerExists(tags[t], names[c])) {
                    emitV4Constants(tags[t], bases[c]);
                }
            }
        }
        vm.writeLine(genV4Path(), "}");
    }

    /// @notice Generate `LibProdDeployCurrent.sol`: unversioned aliases of the
    /// current release tag.
    function genCurrent() internal {
        string memory tag = deployTag();
        string memory suffix = tagSuffix(tag);
        require(vm.exists(LibFs.dirForTag(tag)), "BuildPointers: current tag dir missing");
        string[CONTRACT_COUNT] memory names = contractNames();
        string[CONTRACT_COUNT] memory bases = contractBases();

        writeGeneratedHeader(genCurrentPath());
        vm.writeLine(genCurrentPath(), 'import {LibProdDeployV4} from "./LibProdDeployV4.sol";');
        vm.writeLine(genCurrentPath(), "");
        vm.writeLine(genCurrentPath(), "library LibProdDeployCurrent {");
        vm.writeLine(genCurrentPath(), string.concat('string constant DEPLOY_TAG = "', tag, '";'));
        vm.writeLine(genCurrentPath(), "address constant BEACON_INITIAL_OWNER = LibProdDeployV4.BEACON_INITIAL_OWNER;");
        vm.writeLine(
            genCurrentPath(),
            "address constant STOX_PROD_AUTHORISER_V4_CLONE = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;"
        );
        vm.writeLine(
            genCurrentPath(),
            "bytes32 constant STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH;"
        );
        for (uint256 c = 0; c < CONTRACT_COUNT; c++) {
            if (!pointerExists(tag, names[c])) continue;
            string memory base = bases[c];
            vm.writeLine(
                genCurrentPath(),
                string.concat("address constant ", base, " = LibProdDeployV4.", base, "_", suffix, ";")
            );
            vm.writeLine(
                genCurrentPath(),
                string.concat(
                    "bytes32 constant ", base, "_CODEHASH = LibProdDeployV4.", base, "_CODEHASH_", suffix, ";"
                )
            );
        }
        vm.writeLine(genCurrentPath(), "}");
    }

    function genProdLibs() internal {
        string[] memory tags = deployTags();
        genV4(tags);
        genCurrent();
    }
}
