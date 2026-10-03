// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {VmSafe} from "forge-std-1.16.2/src/Vm.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.37/src/lib/LibCodeGen.sol";
import {LibFs, GENERATED_DIR} from "rain-sol-codegen-0.1.37/src/lib/LibFs.sol";
import {LibGenParseMeta} from "rainlang-interface-0.2.9/src/lib/codegen/LibGenParseMeta.sol";
import {BuildScript} from "rain-deploy-0.1.11/src/abstract/BuildScript.sol";
import {LibRainDeploy} from "rain-deploy-0.1.11/src/lib/LibRainDeploy.sol";
import {LibRainDeploySnapshot} from "rain-deploy-0.1.11/src/lib/LibRainDeploySnapshot.sol";
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

/// One contract's generated deploy pins.
/// @param contractName The snapshot's filename without `.sol`, which
/// `LibFs.pathForTaggedContract` places under `src/generated/<tag>/`, and the
/// contract the artifact is read from.
/// @param constantPrefix The prefix the emitted constants carry, e.g.
/// `STOX_RECEIPT` for `STOX_RECEIPT_0_1_30`.
/// @param creationCode `type(X).creationCode`, which fixes the Zoltu address.
/// @param dependencies The addresses that MUST already carry code on a network
/// before this contract can be broadcast there. Empty is a claim that nothing
/// must pre-exist, so it is only correct for a contract that bakes nothing.
struct GeneratedContract {
    string contractName;
    string constantPrefix;
    bytes creationCode;
    address[] dependencies;
}

contract Build is BuildScript {
    /// @notice How many contracts `generatedContracts()`
    /// enumerate: every candidate-snapshot contract the deploy libs alias.
    uint256 constant CONTRACT_COUNT = 13;

    /// @notice The rolling "current source" snapshot tag — always `candidate`,
    /// never a version number. `src/generated/candidate/` is regenerated from
    /// the current source on every run; a numbered snapshot is frozen only when
    /// a release tag promotes `candidate` (see `script/cut-release.sh`). Source
    /// self-references (`LibProdDeployCurrent`) always resolve to `candidate`,
    /// so they track whatever the source currently compiles to, while numbered
    /// snapshots (`0_1_1`, …) stay frozen and are never regenerated here.
    ///
    /// Aliased from `LibRainDeploySnapshot.CANDIDATE`, which is the directory
    /// `freeze` reads, so the build and the release cannot name different ones.
    function deployTag() internal pure returns (string memory) {
        return LibRainDeploySnapshot.CANDIDATE;
    }

    /// @notice The constant-name suffix for a tag dir. Numbered tags use the tag
    /// verbatim (`0_1_1`); the rolling `candidate` dir uses `CANDIDATE`, so its
    /// generated constants read `STOX_RECEIPT_CANDIDATE` rather than the
    /// lowercase dir name.
    function tagSuffix(string memory tag) internal pure returns (string memory) {
        if (keccak256(bytes(tag)) == keccak256(bytes(LibRainDeploySnapshot.CANDIDATE))) return "CANDIDATE";
        return tag;
    }

    /// @inheritdoc BuildScript
    /// @dev Derived from `generatedContracts()` rather than restated, so a
    /// contract that is built is a contract a release freezes. `freeze` reads
    /// and writes each named snapshot independently, so the order is not
    /// load-bearing here — it is build order because that is the one order the
    /// list has to be in.
    function snapshotContractNames() internal pure override returns (string[] memory) {
        GeneratedContract[] memory contracts = generatedContracts();
        string[] memory names = new string[](contracts.length);
        for (uint256 i = 0; i < contracts.length; i++) {
            names[i] = contracts[i].contractName;
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

        // One pass over `generatedContracts()`, in its order, which is why the
        // list is in build order: each entry's creation code is read after the
        // entries it bakes have been Zoltu-deployed.
        GeneratedContract[] memory contracts = generatedContracts();
        for (uint256 i = 0; i < contracts.length; i++) {
            address deployed = LibRainDeploy.zoltuAddress(contracts[i].creationCode);
            // `writeSnapshot` creates the dir from the same root and tag it
            // derives the path from, so there is no `createDir` here to
            // disagree with it.
            LibRainDeploySnapshot.writeSnapshot(
                vm,
                recordRoot(),
                deployTag(),
                contracts[i].contractName,
                contracts[i].creationCode,
                contracts[i].dependencies
            );

            // The subparser's parse meta and function pointer tables are read
            // back off the instance, so they come from the same build as the
            // snapshot just written. Keyed off the entry rather than hoisted
            // out of the loop, because the tables have to be written after its
            // own snapshot and the loop is what guarantees that.
            if (keccak256(bytes(contracts[i].contractName)) == keccak256("St0xAttestSubParser")) {
                buildSubParserPointers(deployed);
            }
        }
    }

    /// @notice Generates `src/generated/St0xAttestSubParserPointers.sol`: the
    /// described-by meta hash, the parse meta, and the word parser, operand
    /// handler and literal parser pointer tables, read back off the deployed
    /// subparser. `St0xAttestSubParser` imports that file, so its creation
    /// code embeds the tables and the candidate snapshot converges on the
    /// second run after a table changes. Run `script/build-meta.sh` first so
    /// the meta hash is of the current words.
    /// @param subParser The Zoltu address `regenerateSnapshots` wrote the snapshot for.
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
    /// @notice The owner every production beacon is handed at deploy, emitted
    /// into the aggregate deploy lib. A real `address` rather than its text, so
    /// `LibCodeGen.addressConstantString` emits the constant and the Solidity is
    /// not hand-assembled here.
    address constant GEN_OWNER = 0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b;

    /// @notice Every contract this repo generates deploy pins for: the ONE
    /// list, read by every hook.
    ///
    /// It replaces four structures that were keyed by the same thirteen
    /// contracts and connected by nothing — a name list, a constant-prefix
    /// list, the ordered sequence of build calls, and a `keccak256`-dispatched
    /// dependency lookup. A fourteenth contract was four edits that had to
    /// agree, and two of them had already drifted: `StoxUnifiedDeployer` was
    /// fourth in the name list and eighth in the build, and
    /// `StoxCorporateActionsFacet` tenth and first.
    ///
    /// **The order is build order**, which is the order with a real
    /// constraint: a deployer bakes its implementation's address at
    /// construction, so the implementation must already be Zoltu-deployed when
    /// the deployer's creation code is read. The emitted constants follow this
    /// order too, which is why adopting it reordered the generated libs.
    /// @return The generated contracts.
    function generatedContracts() internal pure returns (GeneratedContract[] memory) {
        GeneratedContract[] memory contracts = new GeneratedContract[](CONTRACT_COUNT);

        contracts[0] = GeneratedContract({
            contractName: "StoxCorporateActionsFacet",
            constantPrefix: "STOX_CORPORATE_ACTIONS_FACET",
            creationCode: type(StoxCorporateActionsFacet).creationCode,
            dependencies: new address[](0)
        });
        contracts[1] = GeneratedContract({
            contractName: "StoxReceipt",
            constantPrefix: "STOX_RECEIPT",
            creationCode: type(StoxReceipt).creationCode,
            dependencies: new address[](0)
        });
        contracts[2] = GeneratedContract({
            contractName: "StoxReceiptVault",
            constantPrefix: "STOX_RECEIPT_VAULT",
            creationCode: type(StoxReceiptVault).creationCode,
            dependencies: new address[](0)
        });
        contracts[3] = GeneratedContract({
            contractName: "StoxWrappedTokenVault",
            constantPrefix: "STOX_WRAPPED_TOKEN_VAULT",
            creationCode: type(StoxWrappedTokenVault).creationCode,
            dependencies: new address[](0)
        });
        contracts[4] = GeneratedContract({
            contractName: "StoxWrappedTokenVaultBeacon",
            constantPrefix: "STOX_WRAPPED_TOKEN_VAULT_BEACON",
            creationCode: type(StoxWrappedTokenVaultBeacon).creationCode,
            dependencies: new address[](0)
        });
        contracts[5] = GeneratedContract({
            contractName: "StoxWrappedTokenVaultBeaconSetDeployer",
            constantPrefix: "STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER",
            creationCode: type(StoxWrappedTokenVaultBeaconSetDeployer).creationCode,
            dependencies: dependsOn(LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT_BEACON)
        });
        contracts[6] = GeneratedContract({
            contractName: "StoxOffchainAssetReceiptVaultBeaconSetDeployer",
            constantPrefix: "STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER",
            creationCode: type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode,
            dependencies: dependsOn(LibProdDeployCurrent.STOX_RECEIPT, LibProdDeployCurrent.STOX_RECEIPT_VAULT)
        });
        contracts[7] = GeneratedContract({
            contractName: "StoxUnifiedDeployer",
            constantPrefix: "STOX_UNIFIED_DEPLOYER",
            creationCode: type(StoxUnifiedDeployer).creationCode,
            dependencies: dependsOn(
                LibProdDeployCurrent.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
                LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            )
        });
        contracts[8] = GeneratedContract({
            contractName: "StoxOffchainAssetReceiptVaultAuthorizerV1",
            constantPrefix: "STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1",
            creationCode: type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode,
            dependencies: new address[](0)
        });
        contracts[9] = GeneratedContract({
            contractName: "StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1",
            constantPrefix: "STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1",
            creationCode: type(StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1).creationCode,
            dependencies: new address[](0)
        });
        contracts[10] = GeneratedContract({
            contractName: "ST0xOrchestrator",
            constantPrefix: "ST0X_ORCHESTRATOR",
            creationCode: type(ST0xOrchestrator).creationCode,
            dependencies: new address[](0)
        });
        contracts[11] = GeneratedContract({
            contractName: "ST0xOrchestratorBeaconSetDeployer",
            constantPrefix: "ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER",
            creationCode: type(ST0xOrchestratorBeaconSetDeployer).creationCode,
            dependencies: dependsOn(LibProdDeployCurrent.ST0X_ORCHESTRATOR)
        });
        contracts[12] = GeneratedContract({
            contractName: "St0xAttestSubParser",
            constantPrefix: "ST0X_ATTEST_SUB_PARSER",
            creationCode: type(St0xAttestSubParser).creationCode,
            dependencies: new address[](0)
        });

        return contracts;
    }

    /// @notice A one-address dependency list, so an entry above reads as the
    /// fact it states rather than three lines of array construction.
    /// @param a The address that must already carry code.
    /// @return The list.
    function dependsOn(address a) internal pure returns (address[] memory) {
        address[] memory deps = new address[](1);
        deps[0] = a;
        return deps;
    }

    /// @notice A two-address dependency list.
    /// @param a The first address that must already carry code.
    /// @param b The second.
    /// @return The list.
    function dependsOn(address a, address b) internal pure returns (address[] memory) {
        address[] memory deps = new address[](2);
        deps[0] = a;
        deps[1] = b;
        return deps;
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
    function tagPrecedes(string memory a, string memory b) internal pure returns (bool) {
        if (keccak256(bytes(a)) == keccak256(bytes(LibRainDeploySnapshot.CANDIDATE))) {
            return false;
        }
        if (keccak256(bytes(b)) == keccak256(bytes(LibRainDeploySnapshot.CANDIDATE))) {
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
            if (
                LibRainDeploySnapshot.isTag(name)
                    || keccak256(bytes(name)) == keccak256(bytes(LibRainDeploySnapshot.CANDIDATE))
            ) {
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
    function snapshotPath(string memory tag, string memory name) internal pure returns (string memory) {
        return LibFs.pathForTaggedContract(tag, name);
    }

    /// @notice The file name, rather than the path, of that same snapshot — the
    /// form a generated import line needs.
    /// @param tag The snapshot directory.
    /// @param name The contract name.
    /// @return The final path segment.
    function snapshotFileName(string memory tag, string memory name) internal pure returns (string memory) {
        return LibFs.lastPathSegment(snapshotPath(tag, name));
    }

    function snapshotExists(string memory tag, string memory name) internal view returns (bool) {
        return vm.exists(snapshotPath(tag, name));
    }

    /// @notice Starts `path` with the header every generated file in this org
    /// carries: the SPDX licence, the copyright and the pragma.
    ///
    /// `LibCodeGen.filePrefix()` is that header, built from
    /// `RAIN_SPDX_LICENSE_IDENTIFIER` and `RAIN_COPYRIGHT_TEXT`. Spelling the
    /// two SPDX lines here instead meant this repo had its own copy of the
    /// org's licence text, which would keep emitting the old one after the
    /// canonical constants changed, and the literals had to be fenced off with
    /// `REUSE-IgnoreStart` so the licence lint did not read them as this
    /// script's own header. The function carries that fence itself.
    ///
    /// Truncating rather than appending, so a regeneration replaces the file
    /// instead of growing it.
    /// @param path The file to start.
    function writeGeneratedHeader(string memory path) internal {
        vm.writeFile(path, LibCodeGen.filePrefix());
    }

    function v4ImportLine(string memory name, string memory base, string memory tag)
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
        string memory tail =
            string.concat("_RUNTIME_", suffix, '_GEN} from "./', tag, "/", snapshotFileName(tag, name), '";');
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
        GeneratedContract[] memory contracts = generatedContracts();

        writeGeneratedHeader(genV4Path());
        for (uint256 t = 0; t < tags.length; t++) {
            for (uint256 c = 0; c < CONTRACT_COUNT; c++) {
                if (snapshotExists(tags[t], contracts[c].contractName)) {
                    vm.writeLine(
                        genV4Path(), v4ImportLine(contracts[c].contractName, contracts[c].constantPrefix, tags[t])
                    );
                }
            }
        }
        vm.writeLine(genV4Path(), "");
        vm.writeLine(genV4Path(), "library LibProdDeployV4 {");
        vm.writeLine(
            genV4Path(),
            LibCodeGen.addressConstantString(
                vm, "/// @dev The owner every production beacon is deployed with.", "BEACON_INITIAL_OWNER", GEN_OWNER
            )
        );
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
                if (snapshotExists(tags[t], contracts[c].contractName)) {
                    emitV4Constants(tags[t], contracts[c].constantPrefix);
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
        require(vm.exists(LibFs.dirForTag(tag)), "Build: current tag dir missing");
        GeneratedContract[] memory contracts = generatedContracts();

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
            if (!snapshotExists(tag, contracts[c].contractName)) continue;
            string memory base = contracts[c].constantPrefix;
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
