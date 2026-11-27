// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.41/src/lib/LibRainDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.41/src/lib/LibSafe.sol";
import {DeploySuite} from "rain-deploy-0.1.41/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployZoltuMechanism} from "rain-deploy-0.1.41/src/lib/LibRainDeployZoltuMechanism.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.41/src/lib/LibRegistryAuthority.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.41/src/lib/LibMigrationRegistryDeploy.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.41/src/lib/LibConfigRegistryDeploy.sol";
import {
    BYTECODE_HASH as TIMELOCK_BYTECODE_HASH,
    RUNTIME_CODE as TIMELOCK_RUNTIME_CODE
} from "rain-deploy-0.1.41/src/generated/0_1_18/TimelockController.sol";
import {
    LibExtrospectRegistryBeaconProxy,
    REGISTRY_BEACON_PROXY_PREFIX,
    REGISTRY_BEACON_PROXY_SUFFIX
} from "rain-extrospection-0.1.31/src/lib/LibExtrospectRegistryBeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {
    IOffchainAssetReceiptVaultBeaconSetDeployerV1
} from "rain-vats-0.2.25/src/interface/deprecated/IOffchainAssetReceiptVaultBeaconSetDeployerV1.sol";
import {BuildExpectedState} from "../../script/BuildExpectedState.sol";
import {BuildExpectedStateHarness} from "./BuildExpectedStateHarness.sol";
import {LibLocalProdState} from "../lib/LibLocalProdState.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {IST0xVaultBeaconSet} from "../../src/interface/IST0xVaultBeaconSet.sol";
import {RUNTIME_CODE as SUITE_TIMELOCK_RUNTIME_CODE} from "../../src/generated/candidate/StoxGovernanceTimelock.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibEuAuthoriserClone} from "../../src/lib/LibEuAuthoriserClone.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibProdDeployV1} from "../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV2} from "../../src/lib/LibProdDeployV2.sol";
import {LibProdDeployV2BaseOverrides} from "../../src/lib/LibProdDeployV2BaseOverrides.sol";
import {LibProdTokenConfig, Region, TokenConfig, UnknownUnderlying} from "../../src/lib/LibProdTokenConfig.sol";
import {LibStoxReleasedNetworks} from "../../src/lib/LibStoxReleasedNetworks.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {LibTokenMetadata, TokenMetadataState} from "../../src/lib/LibTokenMetadata.sol";
import {LibProdTokenParams} from "../../src/lib/LibProdTokenParams.sol";
import {LibTestTokenMetadata} from "../lib/LibTestTokenMetadata.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @notice No `zoltu` row carries the key.
error ZoltuRowMissing(string key);

// Fields in key order, the order `parseJsonType` decodes into; the type names are no struct's, so forge keeps it.
string constant TOKEN_JSON = "TokenJson(string assetId,address authoriser,uint256 decimals,string listingName,"
    "string listingTicker,string name,address owner,address receipt,address receiptBeacon,bytes32 receiptCodehash,"
    "address receiptManager,address receiptVault,address receiptVaultBeacon,bytes32 receiptVaultCodehash,"
    "address receiptVaultReceipt,string region,string renamedName,string symbol,string underlying,"
    "address wrappedTokenVault,address wrappedTokenVaultAsset,address wrappedTokenVaultBeacon,"
    "bytes32 wrappedTokenVaultCodehash,uint256 wrappedTokenVaultDecimals,string wrappedTokenVaultName,"
    "string wrappedTokenVaultRenamedName,string wrappedTokenVaultRenamedSymbol,string wrappedTokenVaultSymbol)";
string constant TOKEN_METADATA_JSON = "TokenMetadataJson(string name,string renamedName,string symbol,"
    "string wrappedTokenVaultName,string wrappedTokenVaultRenamedName,string wrappedTokenVaultRenamedSymbol,"
    "string wrappedTokenVaultSymbol)";
string constant QSEP_JSON = "QsepJson(address authoriser,address owner,address receipt,address receiptBeacon,"
    "bytes32 receiptCodehash,address receiptManager,address receiptVault,address receiptVaultBeacon,"
    "bytes32 receiptVaultCodehash,address receiptVaultReceipt,address wrappedTokenVault,address wrappedTokenVaultAsset,"
    "address wrappedTokenVaultBeacon,bytes32 wrappedTokenVaultCodehash)";
string constant BEACON_JSON = "BeaconJson(address beacon,bytes32 codehash,address implementation,address owner,"
    "address renamedImplementation)";
string constant DEPLOYMENT_JSON = "DeploymentJson(address address,bytes32 codehash,string key)";
string constant SAFE_JSON = "SafeJson(address address,address fallbackHandler,bytes32 fallbackHandlerCodehash,"
    "address guard,address[] modules,address[] owners,bytes32[] proxyCodehashes,bytes32[] singletonCodehashes,"
    "address[] singletons,uint256 threshold,string version)";
string constant TIMELOCK_JSON = "TimelockJson(address address,bytes32 codehash,uint256 minDelay)";
string constant ORCHESTRATOR_JSON = "OrchestratorJson(address beacon,bytes32 beaconCodehash,address implementation,"
    "address instance,address owner,address setDeployer)";
string constant AUTHORISER_JSON = "AuthoriserJson(address address,bytes32 codehash)";
string constant REGISTRY_DELEGATE_JSON =
    "RegistryDelegateJson(address account,address delegate,address registry,bool unscoped)";
string constant V2_BEACON_JSON = "V2BeaconJson(address beacon,address implementation,address owner)";

struct ExpectedToken {
    string assetId;
    address authoriser;
    uint256 decimals;
    string listingName;
    string listingTicker;
    string name;
    address owner;
    address receipt;
    address receiptBeacon;
    bytes32 receiptCodehash;
    address receiptManager;
    address receiptVault;
    address receiptVaultBeacon;
    bytes32 receiptVaultCodehash;
    address receiptVaultReceipt;
    string region;
    string renamedName;
    string symbol;
    string underlying;
    address wrappedTokenVault;
    address wrappedTokenVaultAsset;
    address wrappedTokenVaultBeacon;
    bytes32 wrappedTokenVaultCodehash;
    uint256 wrappedTokenVaultDecimals;
    string wrappedTokenVaultName;
    string wrappedTokenVaultRenamedName;
    string wrappedTokenVaultRenamedSymbol;
    string wrappedTokenVaultSymbol;
}

struct ExpectedTokenMetadata {
    string name;
    string renamedName;
    string symbol;
    string wrappedTokenVaultName;
    string wrappedTokenVaultRenamedName;
    string wrappedTokenVaultRenamedSymbol;
    string wrappedTokenVaultSymbol;
}

struct ExpectedQsep {
    address authoriser;
    address owner;
    address receipt;
    address receiptBeacon;
    bytes32 receiptCodehash;
    address receiptManager;
    address receiptVault;
    address receiptVaultBeacon;
    bytes32 receiptVaultCodehash;
    address receiptVaultReceipt;
    address wrappedTokenVault;
    address wrappedTokenVaultAsset;
    address wrappedTokenVaultBeacon;
    bytes32 wrappedTokenVaultCodehash;
}

struct ExpectedBeacon {
    address beacon;
    bytes32 codehash;
    address implementation;
    address owner;
    address renamedImplementation;
}

struct ExpectedDeployment {
    address addr;
    bytes32 codehash;
    string key;
}

struct ExpectedSafe {
    address addr;
    address fallbackHandler;
    bytes32 fallbackHandlerCodehash;
    address guard;
    address[] modules;
    address[] owners;
    bytes32[] proxyCodehashes;
    bytes32[] singletonCodehashes;
    address[] singletons;
    uint256 threshold;
    string version;
}

struct ExpectedTimelock {
    address addr;
    bytes32 codehash;
    uint256 minDelay;
}

struct ExpectedOrchestrator {
    address beacon;
    bytes32 beaconCodehash;
    address implementation;
    address instance;
    address owner;
    address setDeployer;
}

struct ExpectedAuthoriser {
    address addr;
    bytes32 codehash;
}

struct ExpectedRegistryDelegate {
    address account;
    address delegate;
    address registry;
    bool unscoped;
}

struct ExpectedV2Beacon {
    address beacon;
    address implementation;
    address owner;
}

contract BuildExpectedStateTest is Test {
    BuildExpectedState internal build = new BuildExpectedState();

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function testVersionIsOne() external {
        assertEq(vm.parseJsonUint(build.render(), ".version"), 1);
    }

    function testChainsAreTheDeploymentNetworksKeyedByChainId() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        assertEq(vm.parseJsonKeys(json, ".chains").length, nets.length);
        for (uint256 i = 0; i < nets.length; i++) {
            assertEq(vm.parseJsonString(json, string.concat(chain(nets[i]), ".network")), nets[i].name);
        }
    }

    function testEveryObjectCarriesExactlyItsFields() external {
        string memory json = build.render();
        string[] memory root = new string[](3);
        root[0] = "version";
        root[1] = "v2";
        root[2] = "chains";
        assertKeys(json, "", root);
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            string memory at = chain(nets[c]);
            assertKeys(json, at, chainFields(nets[c].chainId));
            if (nets[c].chainId == LibSafeInvariants.BASE_CHAIN_ID) {
                assertKeys(json, string.concat(at, ".qsep"), qsepFields());
            }
            assertRowKeys(json, string.concat(at, ".beacons"), 4, beaconFields());
            assertKeys(json, string.concat(at, ".safe"), safeFields());
            assertKeys(json, string.concat(at, ".timelock"), timelockFields());
            assertKeys(json, string.concat(at, ".orchestrator"), orchestratorFields());
            assertKeys(json, string.concat(at, ".authoriser"), authoriserFields());
            assertKeys(json, string.concat(at, ".euAuthoriser"), authoriserFields());
            assertRowKeys(
                json,
                string.concat(at, ".tokens"),
                LibTokenInvariants.productionTokensForChainId(nets[c].chainId).length,
                tokenFields()
            );
            assertRowKeys(json, string.concat(at, ".zoltu"), expectedZoltu(nets[c]).length, deploymentFields());
            string memory delegates = string.concat(at, ".registryDelegates");
            assertFalse(vm.keyExistsJson(json, index(delegates, 3)), delegates);
            assertKeys(json, index(delegates, 0), registryDelegateFields(false));
            assertKeys(json, index(delegates, 1), registryDelegateFields(true));
            assertKeys(json, index(delegates, 2), registryDelegateFields(false));
        }
        SupportedNetwork[] memory v2 = v2Networks();
        for (uint256 c = 0; c < v2.length; c++) {
            string memory at = v2Chain(v2[c]);
            assertKeys(json, at, v2ChainFields());
            assertRowKeys(json, string.concat(at, ".deployments"), 9, deploymentFields());
            assertKeys(json, string.concat(at, ".receiptBeacon"), v2BeaconFields());
            assertKeys(json, string.concat(at, ".receiptVaultBeacon"), v2BeaconFields());
            assertKeys(json, string.concat(at, ".wrappedTokenVaultBeacon"), v2BeaconFields());
        }
    }

    /// The rows are the four in-use beacons the chain's set deployer getters resolve on a local build, so no row is
    /// left for the dashboard to resolve.
    function testBeaconsAreTheInUseSetAtTheirExpectedImplementationsOwnedByTheTimelock() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            uint256 id = nets[c].chainId;
            address[4] memory resolved = resolvedBeacons(id);
            address[4] memory impls = LibBeaconInvariants.prodExpectedImplementationsForChainId(id);
            bytes32[4] memory codehashes = LibBeaconInvariants.prodBeaconCodehashesForChainId(id);
            uint256 inUse = 4;
            ExpectedBeacon[] memory rows = beaconRows(json, chain(nets[c]));
            assertEq(rows.length, inUse);
            for (uint256 i = 0; i < inUse; i++) {
                assertNotEq(resolved[i], address(0));
                assertEq(rows[i].beacon, resolved[i]);
                assertEq(rows[i].codehash, codehashes[i]);
                assertEq(rows[i].implementation, impls[i]);
                assertEq(rows[i].owner, LibTimelockInvariants.timelockForChainId(id));
            }
        }
    }

    /// The set deployer is the one whose constructor's first and second CREATE are the chain's receipt and
    /// receipt-vault beacons: the V1 set deployer on Base, the 0.1.1 one elsewhere.
    function testBeaconSetDeployerCreatedTheReceiptAndReceiptVaultBeacons() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            uint256 id = nets[c].chainId;
            string memory at = chain(nets[c]);
            address setDeployer = vm.parseJsonAddress(json, string.concat(at, ".beaconSetDeployer"));
            assertEq(
                setDeployer,
                id == LibSafeInvariants.BASE_CHAIN_ID
                    ? LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
                    : LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1
            );
            ExpectedBeacon[] memory beacons = beaconRows(json, at);
            assertEq(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX].beacon, vm.computeCreateAddress(setDeployer, 1));
            assertEq(
                beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX].beacon, vm.computeCreateAddress(setDeployer, 2)
            );
        }
    }

    /// Fixed example from the Ethereum leg: the receipt beacon is the 0.1.1 set deployer's `iReceiptBeacon()` and
    /// serves the 0.1.30 receipt.
    function testEthereumReceiptBeaconIsTheSetDeployersAt0_1_30() external {
        string memory json = build.render();
        LibLocalProdState.beacons(vm, LibSafeInvariants.ETHEREUM_CHAIN_ID);
        address expected = address(
            IST0xVaultBeaconSet(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1)
                .iReceiptBeacon()
        );
        ExpectedBeacon memory row = beaconRows(json, ".chains.1")[0];
        assertNotEq(expected, address(0));
        assertEq(row.beacon, expected);
        assertEq(row.implementation, LibProdDeployV4.STOX_RECEIPT_0_1_30);
        assertEq(
            vm.parseJsonAddress(json, ".chains.1.beaconSetDeployer"),
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1
        );
    }

    /// `renamedImplementation` is what the rename migration's beacon batch upgrades the row's beacon to, and the row's
    /// `implementation` where the batch leaves the beacon alone. Checked on the networks the rename's beacon batch was
    /// cut for: every one before 0G.
    function testRenamedImplementationsAreTheBeaconBatchsUpgrades() external {
        string memory json = build.render();
        LibTestRootLine.etchRegistry(vm);
        SupportedNetwork[] memory nets =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.networksBeforeZerog());
        for (uint256 c = 0; c < nets.length; c++) {
            uint256 snapshot = vm.snapshotState();
            LibLocalProdState.beacons(vm, nets[c].chainId);
            (address[] memory targets,, bytes[] memory payloads) =
                LibUnderlyingNamingRollout.beaconBatch(nets[c].chainId);
            vm.revertToState(snapshot);
            ExpectedBeacon[] memory rows = beaconRows(json, chain(nets[c]));
            uint256 upgraded = 0;
            for (uint256 i = 0; i < 4; i++) {
                upgraded += assertRenamedImplementation(rows[i], targets, payloads);
            }
            assertEq(upgraded, 2);
        }
    }

    /// The number of beacon batch calls that upgrade the row's beacon, each to its `renamedImplementation`.
    function assertRenamedImplementation(ExpectedBeacon memory row, address[] memory targets, bytes[] memory payloads)
        internal
        pure
        returns (uint256)
    {
        uint256 upgrades = 0;
        for (uint256 k = 0; k < targets.length; k++) {
            if (targets[k] == row.beacon) {
                assertEq(payloads[k], abi.encodeCall(UpgradeableBeacon.upgradeTo, (row.renamedImplementation)));
                upgrades++;
            }
        }
        if (upgrades == 0) {
            assertEq(row.renamedImplementation, row.implementation);
        }
        return upgrades;
    }

    /// Every value is concrete: zero appears only as each chain's Safe guard.
    function testZeroIsOnlyTheSafeGuard() external {
        string memory json = build.render();
        assertEq(vm.split(json, vm.toString(address(0))).length - 1, networks().length);
    }

    function testSafeIsTheChainsSafeWithThePinnedPolicy() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            ExpectedSafe memory safe = safeOf(json, chain(nets[i]));
            assertEq(safe.addr, LibSafeInvariants.safeForChainId(nets[i].chainId));
            assertEq(safe.threshold, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
            assertEq(safe.owners, LibSafeInvariants.expectedOwners());
        }
    }

    /// The accepted proxy, singleton and handler hashes are the hashes of the pinned runtime code, singleton i's
    /// hash at index i, so the dashboard's lock-down check matches `LibSafe.assertLockedDown`.
    function testSafeLockDownIsLibSafesAcceptedCode() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            ExpectedSafe memory safe = safeOf(json, chain(nets[i]));
            bytes32[] memory proxies = safe.proxyCodehashes;
            assertEq(proxies.length, 2);
            assertEq(proxies[0], keccak256(LibSafe.SAFE_V1_4_1_PROXY_RUNTIME_CODE));
            assertEq(proxies[0], LibSafe.SAFE_V1_4_1_PROXY_CODEHASH);
            assertEq(proxies[1], keccak256(LibSafe.SAFE_V1_3_0_PROXY_RUNTIME_CODE));
            assertEq(proxies[1], LibSafe.SAFE_V1_3_0_PROXY_CODEHASH);

            address[] memory singletons = safe.singletons;
            bytes32[] memory singletonHashes = safe.singletonCodehashes;
            assertEq(singletons.length, 2);
            assertEq(singletonHashes.length, 2);
            assertEq(singletons[0], LibSafe.SAFE_V1_4_1_L1_SINGLETON);
            assertEq(singletonHashes[0], keccak256(LibSafe.SAFE_V1_4_1_L1_SINGLETON_RUNTIME_CODE));
            assertEq(singletonHashes[0], LibSafe.SAFE_V1_4_1_L1_SINGLETON_CODEHASH);
            assertEq(singletons[1], LibSafe.SAFE_V1_4_1_L2_SINGLETON);
            assertEq(singletonHashes[1], keccak256(LibSafe.SAFE_V1_4_1_L2_SINGLETON_RUNTIME_CODE));
            assertEq(singletonHashes[1], LibSafe.SAFE_V1_4_1_L2_SINGLETON_CODEHASH);

            assertEq(safe.version, LibSafe.SAFE_V1_4_1_VERSION);
            assertEq(safe.modules.length, 0);
            assertEq(safe.guard, address(0));
            assertEq(safe.fallbackHandler, LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER);
            bytes32 handlerHash = safe.fallbackHandlerCodehash;
            assertEq(handlerHash, keccak256(LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER_RUNTIME_CODE));
            assertEq(handlerHash, LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER_CODEHASH);
        }
    }

    function testTimelockIsTheChainsPinAtItsMinDelay() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            uint256 id = nets[i].chainId;
            ExpectedTimelock memory timelock = timelockOf(json, chain(nets[i]));
            assertEq(timelock.addr, LibTimelockInvariants.timelockForChainId(id));
            assertEq(timelock.addr, LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.safeForChainId(id)));
            assertEq(timelock.minDelay, LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        }
    }

    /// The suite timelock's address carries the suite's runtime code, every other address the per-Safe code.
    function testTimelockCodehashIsTheSuiteCodeAtTheSuiteAddressAndThePerSafeCodeElsewhere() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        bool sawPerSafe;
        for (uint256 i = 0; i < nets.length; i++) {
            ExpectedTimelock memory timelock = timelockOf(json, chain(nets[i]));
            bytes32 codehash = timelock.codehash;
            assertEq(codehash, LibTimelockInvariants.timelockCodehash(timelock.addr));
            if (timelock.addr == LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK) {
                assertEq(codehash, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK_CODEHASH);
                assertEq(codehash, keccak256(SUITE_TIMELOCK_RUNTIME_CODE));
            } else {
                assertEq(codehash, TIMELOCK_BYTECODE_HASH);
                assertEq(codehash, keccak256(TIMELOCK_RUNTIME_CODE));
                sawPerSafe = true;
            }
        }
        assertTrue(sawPerSafe);
        assertEq(
            LibTimelockInvariants.timelockCodehash(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK),
            keccak256(SUITE_TIMELOCK_RUNTIME_CODE)
        );
    }

    /// The beacon and instance are the set deployer's nonce 1 and nonce 2 CREATEs, the beacon is a 0.1.30
    /// `UpgradeableBeacon` serving the 0.1.30 orchestrator, and the chain's timelock owns it, on every chain.
    function testOrchestratorIsThe0_1_30BeaconSetOwnedByTheTimelock() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            ExpectedOrchestrator memory orchestrator = orchestratorOf(json, chain(nets[i]));
            address setDeployer = orchestrator.setDeployer;
            assertEq(setDeployer, LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30);
            assertEq(orchestrator.beacon, LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON);
            assertEq(orchestrator.beacon, vm.computeCreateAddress(setDeployer, 1));
            assertEq(orchestrator.instance, LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);
            assertEq(orchestrator.instance, vm.computeCreateAddress(setDeployer, 2));
            assertEq(orchestrator.beaconCodehash, LibBeaconInvariants.UPGRADEABLE_BEACON_CODEHASH_0_1_30);
            assertEq(orchestrator.implementation, LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30);
            assertEq(orchestrator.owner, LibTimelockInvariants.timelockForChainId(nets[i].chainId));
        }
    }

    /// The orchestrator's implementation and set deployer are the released 0.1.30 Zoltu suites on every chain.
    function testOrchestratorCodeIsItsReleasedZoltuSuites() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            string memory at = chain(nets[i]);
            ExpectedDeployment[] memory zoltu = deploymentRows(json, string.concat(at, ".zoltu"));
            ExpectedOrchestrator memory orchestrator = orchestratorOf(json, at);
            assertEq(zoltuAddress(zoltu, "stox-orchestrator@0_1_30"), orchestrator.implementation);
            assertEq(zoltuAddress(zoltu, "stox-orchestrator-beacon-set-deployer@0_1_30"), orchestrator.setDeployer);
        }
    }

    function testAuthorisersAreTheChainsClonesAtTheCloneCodehash() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            uint256 id = nets[i].chainId;
            string memory at = chain(nets[i]);
            ExpectedAuthoriser memory authoriser = authoriserOf(json, string.concat(at, ".authoriser"));
            assertEq(authoriser.addr, LibAuthoriserInvariants.authoriserForChainId(id));
            assertEq(authoriser.codehash, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH);
            ExpectedAuthoriser memory eu = authoriserOf(json, string.concat(at, ".euAuthoriser"));
            assertEq(eu.addr, LibAuthoriserInvariants.euAuthoriserForChainId(id));
            assertEq(eu.addr, LibEuAuthoriserClone.cloneDeployedAddress(id));
            assertEq(eu.codehash, keccak256(LibEuAuthoriserClone.cloneRuntimeCode()));
        }
    }

    function testTokensAreTheChainsTableWithRegionRoutedAuthorisers() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            uint256 id = nets[c].chainId;
            TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(id);
            ExpectedToken[] memory rows = tokenRows(json, chain(nets[c]));
            assertEq(rows.length, tokens.length);
            for (uint256 i = 0; i < tokens.length; i++) {
                ExpectedToken memory row = rows[i];
                TokenConfig memory config = LibProdTokenConfig.configOf(tokens[i].underlying);
                assertEq(row.underlying, tokens[i].underlying);
                assertEq(row.assetId, config.assetId.id);
                assertEq(row.listingTicker, config.listingTicker);
                assertEq(row.listingName, config.listingName);
                assertEq(row.name, config.name);
                assertEq(row.symbol, config.symbol);
                assertEq(row.receiptVault, tokens[i].receiptVault);
                assertEq(row.receipt, tokens[i].receipt);
                assertEq(row.wrappedTokenVault, tokens[i].wrappedTokenVault);
                assertEq(row.owner, LibTimelockInvariants.timelockForChainId(id));
                address expected = config.region == Region.EU
                    ? LibAuthoriserInvariants.euAuthoriserForChainId(id)
                    : LibAuthoriserInvariants.authoriserForChainId(id);
                assertEq(row.authoriser, expected);
            }
        }
    }

    /// Fixed examples on Base: tMC is the EU token, on the EU clone; tMSTR is US, on the V4 clone.
    function testBaseMcIsOnTheEuCloneAndMstrOnTheV4Clone() external {
        ExpectedToken[] memory rows = tokenRows(build.render(), ".chains.8453");
        uint256 n = LibTokenInvariants.productionTokensBase().length;
        bool sawMc;
        bool sawMstr;
        for (uint256 i = 0; i < n; i++) {
            bytes32 underlying = keccak256(bytes(rows[i].underlying));
            address authoriser = rows[i].authoriser;
            if (underlying == keccak256("MC")) {
                assertEq(authoriser, 0xDB9152e46c1D140DB6a6f814461f21c571F3275e);
                sawMc = true;
            } else if (underlying == keccak256("MSTR")) {
                assertEq(authoriser, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE);
                sawMstr = true;
            }
        }
        assertTrue(sawMc && sawMstr);
    }

    /// Fixed examples on Base: tMC is EU, tMSTR is US.
    function testBaseMcRegionIsEuAndMstrRegionIsUs() external {
        ExpectedToken[] memory rows = tokenRows(build.render(), ".chains.8453");
        uint256 n = LibTokenInvariants.productionTokensBase().length;
        bool sawMc;
        bool sawMstr;
        for (uint256 i = 0; i < n; i++) {
            bytes32 underlying = keccak256(bytes(rows[i].underlying));
            if (underlying == keccak256("MC")) {
                assertEq(rows[i].region, "EU");
                sawMc = true;
            } else if (underlying == keccak256("MSTR")) {
                assertEq(rows[i].region, "US");
                sawMstr = true;
            }
        }
        assertTrue(sawMc && sawMstr);
    }

    /// The unprefixed fields are the initialized metadata, the `renamed` fields the metadata once the rename batch has
    /// run, which renames only its leading rows; each set is one consistent state of the vault and wrapper.
    function testTokenMetadataIsTheInitializedAndRenamedStates() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(nets[c].chainId);
            ExpectedTokenMetadata[] memory rows = abi.decode(
                vm.parseJsonTypeArray(json, string.concat(chain(nets[c]), ".tokens"), TOKEN_METADATA_JSON),
                (ExpectedTokenMetadata[])
            );
            // The batches were not cut for 0G (`testZerogRenamesNothing`).
            bool chainRenames = LibRainDeploy.hasChainId(
                LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.networksBeforeZerog()), nets[c].chainId
            );
            for (uint256 i = 0; i < tokens.length; i++) {
                TokenConfig memory config = LibProdTokenConfig.configOf(tokens[i].underlying);
                TokenMetadataState state = tokens[i].receiptVault == LibProdTokenParams.tokenAddress(config)
                    ? TokenMetadataState.Listed
                    : TokenMetadataState.Initialized;
                assertTokenMetadata(
                    rows[i],
                    config,
                    state,
                    chainRenames && LibUnderlyingNamingRollout.renamesRow(i) ? TokenMetadataState.Renamed : state
                );
            }
        }
    }

    function assertTokenMetadata(
        ExpectedTokenMetadata memory metadata,
        TokenConfig memory config,
        TokenMetadataState state,
        TokenMetadataState renamedState
    ) internal pure {
        assertMetadataState(
            config,
            state,
            metadata.name,
            metadata.symbol,
            metadata.wrappedTokenVaultName,
            metadata.wrappedTokenVaultSymbol
        );
        assertMetadataState(
            config,
            renamedState,
            metadata.renamedName,
            metadata.symbol,
            metadata.wrappedTokenVaultRenamedName,
            metadata.wrappedTokenVaultRenamedSymbol
        );
        if (state == TokenMetadataState.Initialized) {
            assertEq(
                LibTestTokenMetadata.vaultRenamed(config, metadata.renamedName),
                renamedState == TokenMetadataState.Renamed
            );
        }
    }

    function assertMetadataState(
        TokenConfig memory config,
        TokenMetadataState state,
        string memory name,
        string memory symbol,
        string memory wrappedName,
        string memory wrappedSymbol
    ) internal pure {
        assertEq(name, LibTokenMetadata.vaultName(config, state));
        assertEq(symbol, LibTokenMetadata.vaultSymbol(config, state));
        assertEq(wrappedName, LibTokenMetadata.wrappedName(config, state));
        assertEq(wrappedSymbol, LibTokenMetadata.wrappedSymbol(config, state));
        assertTrue(LibTestTokenMetadata.consistent(config, name, symbol, wrappedName, wrappedSymbol));
    }

    function testTokenDecimalsAreTheVaultAndWrapperDecimals() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            ExpectedToken[] memory rows = tokenRows(json, chain(nets[c]));
            uint256 n = LibTokenInvariants.productionTokensForChainId(nets[c].chainId).length;
            for (uint256 i = 0; i < n; i++) {
                assertEq(rows[i].decimals, LibTokenMetadata.RECEIPT_VAULT_DECIMALS);
                assertEq(rows[i].wrappedTokenVaultDecimals, LibTokenMetadata.WRAPPED_TOKEN_VAULT_DECIMALS);
            }
        }
    }

    function testTokenVaultReceiptManagerAndWrapperAssetAreTheRowsOwnLegs() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(nets[c].chainId);
            ExpectedToken[] memory rows = tokenRows(json, chain(nets[c]));
            for (uint256 i = 0; i < tokens.length; i++) {
                assertEq(rows[i].receiptVaultReceipt, tokens[i].receipt);
                assertEq(rows[i].receiptManager, tokens[i].receiptVault);
                assertEq(rows[i].wrappedTokenVaultAsset, tokens[i].receiptVault);
            }
        }
    }

    /// Each leg's beacon is the beacon the chain's set deployer getters resolve for that leg.
    function testTokenLegBeaconsAreTheChainsBeaconRows() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            uint256 id = nets[c].chainId;
            string memory at = chain(nets[c]);
            address[4] memory resolved = resolvedBeacons(id);
            ExpectedBeacon[] memory beacons = beaconRows(json, at);
            address receiptBeacon = beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX].beacon;
            address vaultBeacon = beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX].beacon;
            address wrapperBeacon = beacons[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX].beacon;
            assertEq(receiptBeacon, resolved[LibBeaconInvariants.RECEIPT_BEACON_INDEX]);
            assertEq(vaultBeacon, resolved[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]);
            assertEq(wrapperBeacon, resolved[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX]);
            ExpectedToken[] memory rows = tokenRows(json, at);
            uint256 n = LibTokenInvariants.productionTokensForChainId(id).length;
            for (uint256 i = 0; i < n; i++) {
                assertEq(rows[i].receiptBeacon, receiptBeacon);
                assertEq(rows[i].receiptVaultBeacon, vaultBeacon);
                assertEq(rows[i].wrappedTokenVaultBeacon, wrapperBeacon);
            }
        }
    }

    /// Base's token proxies are the V1 build, pinned by codehash.
    function testBaseTokenLegCodehashesAreTheV1ProxyPins() external {
        ExpectedToken[] memory rows = tokenRows(build.render(), ".chains.8453");
        uint256 n = LibTokenInvariants.productionTokensBase().length;
        for (uint256 i = 0; i < n; i++) {
            assertEq(rows[i].receiptCodehash, LibProdDeployV1.PROD_STOX_RECEIPT_PROXY_BASE_CODEHASH_V1);
            assertEq(rows[i].receiptVaultCodehash, LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_PROXY_BASE_CODEHASH_V1);
            assertEq(
                rows[i].wrappedTokenVaultCodehash, LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_PROXY_BASE_CODEHASH_V1
            );
        }
    }

    /// tQSEP, outside the token table, is on Base only: its own legs on Base's beacon rows at the Base V1 proxy pins,
    /// owned by Base's timelock and authorised by the fleet authoriser.
    function testQsepIsBaseOnlyOnTheBaseBeaconsWithTheTimelockAndFleetAuthoriser() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        bool sawBase;
        for (uint256 c = 0; c < nets.length; c++) {
            bool isBase = nets[c].chainId == LibSafeInvariants.BASE_CHAIN_ID;
            sawBase = sawBase || isBase;
            assertEq(vm.keyExistsJson(json, string.concat(chain(nets[c]), ".qsep")), isBase, nets[c].name);
        }
        assertTrue(sawBase);
        ExpectedQsep memory qsep = abi.decode(vm.parseJsonType(json, ".chains.8453.qsep", QSEP_JSON), (ExpectedQsep));
        address vault = LibTokenInvariants.QSEP_RECEIPT_VAULT;
        address receipt = LibTokenInvariants.QSEP_RECEIPT;
        assertEq(qsep.receiptVault, vault);
        assertEq(qsep.receipt, receipt);
        assertEq(qsep.wrappedTokenVault, LibTokenInvariants.QSEP_WRAPPED_TOKEN_VAULT);
        assertEq(qsep.receiptVaultReceipt, receipt);
        assertEq(qsep.receiptManager, vault);
        assertEq(qsep.wrappedTokenVaultAsset, vault);
        assertQsepBeacons(json, qsep);
        assertEq(qsep.receiptCodehash, LibProdDeployV1.PROD_STOX_RECEIPT_PROXY_BASE_CODEHASH_V1);
        assertEq(qsep.receiptVaultCodehash, LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_PROXY_BASE_CODEHASH_V1);
        assertEq(qsep.wrappedTokenVaultCodehash, LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_PROXY_BASE_CODEHASH_V1);
        assertEq(qsep.owner, LibTimelockInvariants.timelockForChainId(LibSafeInvariants.BASE_CHAIN_ID));
        assertEq(qsep.owner, vm.parseJsonAddress(json, ".chains.8453.timelock.address"));
        assertEq(qsep.authoriser, LibAuthoriserInvariants.STOX_PROD_AUTHORISER);
        assertEq(qsep.authoriser, vm.parseJsonAddress(json, ".chains.8453.authoriser.address"));
    }

    /// Each tQSEP leg's beacon is Base's beacon row for that leg, as Base's set deployer getters resolve it.
    function assertQsepBeacons(string memory json, ExpectedQsep memory qsep) internal {
        address[4] memory resolved = resolvedBeacons(LibSafeInvariants.BASE_CHAIN_ID);
        ExpectedBeacon[] memory base = beaconRows(json, ".chains.8453");
        uint256[3] memory legs = [
            LibBeaconInvariants.RECEIPT_BEACON_INDEX,
            LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX,
            LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX
        ];
        address[3] memory beacons = [qsep.receiptBeacon, qsep.receiptVaultBeacon, qsep.wrappedTokenVaultBeacon];
        string[3] memory keys = ["receiptBeacon", "receiptVaultBeacon", "wrappedTokenVaultBeacon"];
        for (uint256 i = 0; i < legs.length; i++) {
            assertEq(beacons[i], base[legs[i]].beacon, keys[i]);
            assertEq(beacons[i], resolved[legs[i]], keys[i]);
        }
    }

    /// Off Base each leg is a `RegistryBeaconProxy` over its in-use beacon: the receipt and receipt-vault beacons are
    /// the set deployer's first and second CREATE, the wrapper beacon is pinned.
    function testOffBaseTokenLegCodehashesAreRegistryBeaconProxiesOverTheInUseBeacons() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        uint256 checked = 0;
        for (uint256 c = 0; c < nets.length; c++) {
            uint256 id = nets[c].chainId;
            if (id == LibSafeInvariants.BASE_CHAIN_ID) {
                continue;
            }
            assertOffBaseTokenLegCodehashes(json, nets[c]);
            checked++;
        }
        assertEq(checked, nets.length - 1);
    }

    function assertOffBaseTokenLegCodehashes(string memory json, SupportedNetwork memory network) internal pure {
        string memory at = chain(network);
        address setDeployer = vm.parseJsonAddress(json, string.concat(at, ".beaconSetDeployer"));
        assertNotEq(setDeployer, address(0));
        bytes32 receiptHash = registryBeaconProxyCodehash(vm.computeCreateAddress(setDeployer, 1));
        bytes32 vaultHash = registryBeaconProxyCodehash(vm.computeCreateAddress(setDeployer, 2));
        bytes32 wrapperHash = registryBeaconProxyCodehash(
            beaconRows(json, at)[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX].beacon
        );
        ExpectedToken[] memory rows = tokenRows(json, at);
        uint256 n = LibTokenInvariants.productionTokensForChainId(network.chainId).length;
        for (uint256 i = 0; i < n; i++) {
            assertEq(rows[i].receiptCodehash, receiptHash);
            assertEq(rows[i].receiptVaultCodehash, vaultHash);
            assertEq(rows[i].wrappedTokenVaultCodehash, wrapperHash);
        }
    }

    /// The upgrade migration is the beacon batch's record, the id of the script that schedules it.
    function testUpgradeMigrationIsTheBeaconBatchRecord() external {
        string memory json = build.render();
        string memory script = "script/20261021-schedule-underlying-naming-beacons.s.sol";
        assertTrue(vm.exists(script));
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            bytes32 id = vm.parseJsonBytes32(json, string.concat(chain(nets[c]), ".upgradeMigration"));
            assertEq(id, LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS);
            assertEq(id, keccak256(bytes(script)));
        }
    }

    /// The rename migration is the rename batch's record, the id of the script that schedules it.
    function testRenameMigrationIsTheRenameBatchRecord() external {
        string memory json = build.render();
        string memory script = "script/20261021-schedule-underlying-naming-rename.s.sol";
        assertTrue(vm.exists(script));
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            bytes32 id = vm.parseJsonBytes32(json, string.concat(chain(nets[c]), ".renameMigration"));
            assertEq(id, LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME);
            assertEq(id, keccak256(bytes(script)));
        }
    }

    /// The underlying naming's batches were cut for the networks before 0G only: on 0G each beacon's
    /// `renamedImplementation` is its implementation, and a token's renamed metadata is its current metadata.
    function testZerogRenamesNothing() external {
        uint256 id = LibSafeInvariants.ZEROG_CHAIN_ID;
        ExpectedBeacon[] memory beacons = beaconRows(build.render(), string.concat(".chains.", vm.toString(id)));
        for (uint256 i = 0; i < 4; i++) {
            assertEq(beacons[i].renamedImplementation, beacons[i].implementation);
        }

        BuildExpectedStateHarness harness = new BuildExpectedStateHarness();
        assertTrue(LibUnderlyingNamingRollout.renamesRow(0), "row 0 renames on a full line");
        TokenInstance memory token = LibTokenInvariants.productionTokensForChainId(id)[0];
        assertEq(token.underlying, "MSTR");
        TokenConfig memory config = LibProdTokenConfig.configOf("MSTR");
        string memory zerog = harness.tokenMetadata(id, 0, token);
        assertTokenMetadata(
            tokenMetadataOf(zerog), config, TokenMetadataState.Initialized, TokenMetadataState.Initialized
        );
        string memory base = harness.tokenMetadata(LibSafeInvariants.BASE_CHAIN_ID, 0, token);
        assertTokenMetadata(tokenMetadataOf(base), config, TokenMetadataState.Initialized, TokenMetadataState.Renamed);
    }

    /// A token at its suite's address was initialized from the row's listing, so its metadata is the
    /// listed state.
    function testATokenAtItsSuiteAddressIsListed() external {
        BuildExpectedStateHarness harness = new BuildExpectedStateHarness();
        TokenConfig memory config = LibProdTokenConfig.configOf("MSTR");
        TokenInstance memory token = TokenInstance({
            underlying: "MSTR",
            receipt: address(0),
            receiptVault: LibProdTokenParams.tokenAddress(config),
            wrappedTokenVault: address(0)
        });
        ExpectedTokenMetadata memory zerog =
            tokenMetadataOf(harness.tokenMetadata(LibSafeInvariants.ZEROG_CHAIN_ID, 0, token));
        assertTokenMetadata(zerog, config, TokenMetadataState.Listed, TokenMetadataState.Listed);
        assertEq(zerog.symbol, string.concat("t", config.listingTicker));
    }

    function testV2IsTheV2NetworksKeyedByChainId() external {
        string memory json = build.render();
        SupportedNetwork[] memory v2 = v2Networks();
        assertEq(vm.parseJsonKeys(json, ".v2").length, v2.length);
        for (uint256 i = 0; i < v2.length; i++) {
            assertEq(vm.parseJsonString(json, string.concat(v2Chain(v2[i]), ".network")), v2[i].name);
        }
    }

    function testV2DeploymentsAreTheLibProdDeployV2Pins() external {
        string memory json = build.render();
        string[] memory keys = new string[](9);
        address[] memory addresses = new address[](9);
        bytes32[] memory codehashes = new bytes32[](9);
        keys[0] = "StoxReceipt";
        addresses[0] = LibProdDeployV2.STOX_RECEIPT;
        codehashes[0] = LibProdDeployV2.STOX_RECEIPT_CODEHASH;
        keys[1] = "StoxReceiptVault";
        addresses[1] = LibProdDeployV2.STOX_RECEIPT_VAULT;
        codehashes[1] = LibProdDeployV2.STOX_RECEIPT_VAULT_CODEHASH;
        keys[2] = "StoxWrappedTokenVault";
        addresses[2] = LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT;
        codehashes[2] = LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_CODEHASH;
        keys[3] = "StoxUnifiedDeployer";
        addresses[3] = LibProdDeployV2.STOX_UNIFIED_DEPLOYER;
        codehashes[3] = LibProdDeployV2.STOX_UNIFIED_DEPLOYER_CODEHASH;
        keys[4] = "StoxWrappedTokenVaultBeacon";
        addresses[4] = LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON;
        codehashes[4] = LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH;
        keys[5] = "StoxOffchainAssetReceiptVaultBeaconSetDeployer";
        addresses[5] = LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER;
        codehashes[5] = LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH;
        keys[6] = "StoxWrappedTokenVaultBeaconSetDeployer";
        addresses[6] = LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER;
        codehashes[6] = LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH;
        keys[7] = "StoxOffchainAssetReceiptVaultAuthorizerV1";
        addresses[7] = LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1;
        codehashes[7] = LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH;
        keys[8] = "StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1";
        addresses[8] = LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1;
        codehashes[8] = LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH;
        SupportedNetwork[] memory v2 = v2Networks();
        for (uint256 c = 0; c < v2.length; c++) {
            ExpectedDeployment[] memory rows = deploymentRows(json, string.concat(v2Chain(v2[c]), ".deployments"));
            assertEq(rows.length, keys.length);
            for (uint256 i = 0; i < keys.length; i++) {
                assertEq(rows[i].key, keys[i]);
                assertEq(rows[i].addr, addresses[i]);
                assertEq(rows[i].codehash, codehashes[i]);
            }
        }
    }

    /// The receipt and receipt-vault beacons are the V2 set deployer's getters on a local Zoltu deploy and serve the V2
    /// receipt and vault from the V2 owner, except on Base, which carries its overrides; the wrapper beacon is the
    /// deployed one.
    function testV2BeaconsAreTheSetDeployersWithBaseOverrides() external {
        string memory json = build.render();
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(LibProdDeployV2.PROD_STOX_RECEIPT_CREATION_BYTECODE_V2);
        LibRainDeploy.deployZoltu(LibProdDeployV2.PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V2);
        IOffchainAssetReceiptVaultBeaconSetDeployerV1 deployed = IOffchainAssetReceiptVaultBeaconSetDeployerV1(
            LibRainDeploy.deployZoltu(
                LibProdDeployV2.PROD_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V2
            )
        );
        assertEq(address(deployed), LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER);
        address receiptBeacon = address(deployed.I_RECEIPT_BEACON());
        address vaultBeacon = address(deployed.I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON());
        assertNotEq(receiptBeacon, address(0));
        assertNotEq(vaultBeacon, address(0));
        SupportedNetwork[] memory v2 = v2Networks();
        bool sawBase;
        for (uint256 c = 0; c < v2.length; c++) {
            string memory at = v2Chain(v2[c]);
            bool isBase = v2[c].chainId == LibSafeInvariants.BASE_CHAIN_ID;
            sawBase = sawBase || isBase;
            address setDeployer = vm.parseJsonAddress(json, string.concat(at, ".beaconSetDeployer"));
            ExpectedDeployment[] memory deployments = deploymentRows(json, string.concat(at, ".deployments"));
            assertEq(setDeployer, LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER);
            assertEq(setDeployer, deployments[5].addr);
            assertV2Beacon(
                v2BeaconOf(json, string.concat(at, ".receiptBeacon")),
                receiptBeacon,
                isBase ? LibProdDeployV2BaseOverrides.RECEIPT_BEACON_IMPLEMENTATION : LibProdDeployV2.STOX_RECEIPT,
                isBase ? LibProdDeployV2BaseOverrides.RECEIPT_BEACON_OWNER : LibProdDeployV2.BEACON_INITIAL_OWNER
            );
            assertV2Beacon(
                v2BeaconOf(json, string.concat(at, ".receiptVaultBeacon")),
                vaultBeacon,
                isBase ? LibProdDeployV2BaseOverrides.VAULT_BEACON_IMPLEMENTATION : LibProdDeployV2.STOX_RECEIPT_VAULT,
                isBase ? LibProdDeployV2BaseOverrides.VAULT_BEACON_OWNER : LibProdDeployV2.BEACON_INITIAL_OWNER
            );
            ExpectedV2Beacon memory wrapper = v2BeaconOf(json, string.concat(at, ".wrappedTokenVaultBeacon"));
            assertV2Beacon(
                wrapper,
                deployments[4].addr,
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT,
                LibProdDeployV2.BEACON_INITIAL_OWNER
            );
            assertEq(wrapper.beacon, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON);
        }
        assertTrue(sawBase);
    }

    /// Every released Zoltu suite naming the chain, or naming no networks (so every declared one), in release order,
    /// at its recorded address with the hash of its recorded runtime code.
    function testZoltuIsEveryReleasedZoltuSuiteOnTheChain() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            DeploySuite[] memory suites = expectedZoltu(nets[c]);
            assertGt(suites.length, 0);
            ExpectedDeployment[] memory rows = deploymentRows(json, string.concat(chain(nets[c]), ".zoltu"));
            assertEq(rows.length, suites.length);
            for (uint256 i = 0; i < suites.length; i++) {
                assertEq(rows[i].key, suites[i].suite);
                assertEq(rows[i].addr, suites[i].storedDeployedAddress);
                assertEq(rows[i].codehash, suites[i].storedBytecodeHash);
                assertEq(rows[i].codehash, keccak256(suites[i].storedRuntimeCode));
            }
        }
    }

    function testRegistryDelegatesAreTheRootsExpectedDelegations() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            uint256 id = nets[c].chainId;
            address safe = LibSafeInvariants.safeForChainId(id);
            string memory list = string.concat(chain(nets[c]), ".registryDelegates");
            ExpectedRegistryDelegate[] memory rows =
                abi.decode(vm.parseJsonTypeArray(json, list, REGISTRY_DELEGATE_JSON), (ExpectedRegistryDelegate[]));
            assertEq(rows.length, 3);
            assertRegistryDelegate(rows[0], LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, safe, true);
            assertRegistryDelegate(
                rows[1],
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
                LibTimelockInvariants.timelockForChainId(id),
                false
            );
            assertEq(vm.parseJsonBytes32(json, string.concat(index(list, 1), ".scope")), LibStoxMigrations.NAMESPACE);
            assertRegistryDelegate(rows[2], LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, safe, true);
        }
    }

    function assertRegistryDelegate(
        ExpectedRegistryDelegate memory row,
        address registry,
        address delegate,
        bool unscoped
    ) internal pure {
        assertEq(row.registry, registry);
        assertEq(row.account, LibRegistryAuthority.ROOT_AUTHORITY);
        assertEq(row.delegate, delegate);
        assertEq(row.unscoped, unscoped);
    }

    function testUnknownUnderlyingRevertsTyped() external {
        BuildExpectedStateHarness harness = new BuildExpectedStateHarness();
        vm.expectRevert(abi.encodeWithSelector(UnknownUnderlying.selector, "NOPE"));
        harness.callTokenMetadataJson(
            LibSafeInvariants.BASE_CHAIN_ID,
            "row",
            0,
            TokenInstance({
                underlying: "NOPE", receipt: address(0), receiptVault: address(0), wrappedTokenVault: address(0)
            })
        );
    }

    function testRunWritesTheRender() external {
        vm.removeFile("expected-state.json");
        build.run();
        assertEq(keccak256(vm.parseJson(vm.readFile("expected-state.json"))), keccak256(vm.parseJson(build.render())));
    }

    function expectedZoltu(SupportedNetwork memory network) internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory released = LibStoxReleasedNetworks.releasedSuites();
        bool[] memory on = new bool[](released.length);
        uint256 count = 0;
        bytes32 zoltu = keccak256(LibRainDeployZoltuMechanism.mechanismData());
        for (uint256 i = 0; i < released.length; i++) {
            on[i] = keccak256(released[i].mechanismData) == zoltu && names(released[i].networks, network.name);
            if (on[i]) {
                count++;
            }
        }
        DeploySuite[] memory suites = new DeploySuite[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < released.length; i++) {
            if (on[i]) {
                suites[j++] = released[i];
            }
        }
        return suites;
    }

    function names(string[] memory declared, string memory name) internal pure returns (bool) {
        if (declared.length == 0) {
            return true;
        }
        for (uint256 i = 0; i < declared.length; i++) {
            if (keccak256(bytes(declared[i])) == keccak256(bytes(name))) {
                return true;
            }
        }
        return false;
    }

    function zoltuAddress(ExpectedDeployment[] memory rows, string memory key) internal pure returns (address) {
        for (uint256 i = 0; i < rows.length; i++) {
            if (keccak256(bytes(rows[i].key)) == keccak256(bytes(key))) {
                return rows[i].addr;
            }
        }
        revert ZoltuRowMissing(key);
    }

    function assertKeys(string memory json, string memory at, string[] memory expected) internal pure {
        string[] memory keys = vm.parseJsonKeys(json, bytes(at).length == 0 ? "$" : at);
        assertEq(keys.length, expected.length, at);
        for (uint256 i = 0; i < expected.length; i++) {
            assertTrue(contains(keys, expected[i]), string.concat(at, ".", expected[i]));
        }
    }

    function contains(string[] memory keys, string memory key) internal pure returns (bool) {
        for (uint256 i = 0; i < keys.length; i++) {
            if (keccak256(bytes(keys[i])) == keccak256(bytes(key))) {
                return true;
            }
        }
        return false;
    }

    function assertRowKeys(string memory json, string memory list, uint256 rows, string[] memory expected)
        internal
        view
    {
        assertFalse(vm.keyExistsJson(json, index(list, rows)), list);
        for (uint256 i = 0; i < rows; i++) {
            assertKeys(json, index(list, i), expected);
        }
    }

    function tokenRows(string memory json, string memory at) internal pure returns (ExpectedToken[] memory) {
        return abi.decode(vm.parseJsonTypeArray(json, string.concat(at, ".tokens"), TOKEN_JSON), (ExpectedToken[]));
    }

    function tokenMetadataOf(string memory json) internal pure returns (ExpectedTokenMetadata memory) {
        return abi.decode(vm.parseJsonType(json, TOKEN_METADATA_JSON), (ExpectedTokenMetadata));
    }

    function beaconRows(string memory json, string memory at) internal pure returns (ExpectedBeacon[] memory) {
        return abi.decode(vm.parseJsonTypeArray(json, string.concat(at, ".beacons"), BEACON_JSON), (ExpectedBeacon[]));
    }

    function deploymentRows(string memory json, string memory list)
        internal
        pure
        returns (ExpectedDeployment[] memory)
    {
        return abi.decode(vm.parseJsonTypeArray(json, list, DEPLOYMENT_JSON), (ExpectedDeployment[]));
    }

    function safeOf(string memory json, string memory at) internal pure returns (ExpectedSafe memory) {
        return abi.decode(vm.parseJsonType(json, string.concat(at, ".safe"), SAFE_JSON), (ExpectedSafe));
    }

    function timelockOf(string memory json, string memory at) internal pure returns (ExpectedTimelock memory) {
        return abi.decode(vm.parseJsonType(json, string.concat(at, ".timelock"), TIMELOCK_JSON), (ExpectedTimelock));
    }

    function orchestratorOf(string memory json, string memory at) internal pure returns (ExpectedOrchestrator memory) {
        return abi.decode(
            vm.parseJsonType(json, string.concat(at, ".orchestrator"), ORCHESTRATOR_JSON), (ExpectedOrchestrator)
        );
    }

    function authoriserOf(string memory json, string memory key) internal pure returns (ExpectedAuthoriser memory) {
        return abi.decode(vm.parseJsonType(json, key, AUTHORISER_JSON), (ExpectedAuthoriser));
    }

    function v2BeaconOf(string memory json, string memory key) internal pure returns (ExpectedV2Beacon memory) {
        return abi.decode(vm.parseJsonType(json, key, V2_BEACON_JSON), (ExpectedV2Beacon));
    }

    /// The chain's beacons as its set deployer getters resolve them on a local build of the chain's beacons.
    function resolvedBeacons(uint256 chainId) internal returns (address[4] memory) {
        uint256 snapshot = vm.snapshotState();
        LibLocalProdState.beacons(vm, chainId);
        address[4] memory resolved = LibBeaconInvariants.prodBeaconsForChainId(chainId);
        vm.revertToState(snapshot);
        return resolved;
    }

    /// The codehash of a `RegistryBeaconProxy` over `beacon`, its code checked to be one by extrospection.
    function registryBeaconProxyCodehash(address beacon) internal pure returns (bytes32) {
        bytes memory code = abi.encodePacked(
            REGISTRY_BEACON_PROXY_PREFIX, bytes32(uint256(uint160(beacon))), REGISTRY_BEACON_PROXY_SUFFIX
        );
        (bool isProxy, address proxied) = LibExtrospectRegistryBeaconProxy.isRegistryBeaconProxy(code);
        assertTrue(isProxy);
        assertEq(proxied, beacon);
        return keccak256(code);
    }

    function assertV2Beacon(ExpectedV2Beacon memory row, address beacon, address implementation, address owner)
        internal
        pure
    {
        assertEq(row.beacon, beacon);
        assertEq(row.implementation, implementation);
        assertEq(row.owner, owner);
    }

    function chainFields(uint256 chainId) internal pure returns (string[] memory) {
        bool isBase = chainId == LibSafeInvariants.BASE_CHAIN_ID;
        string[] memory fields = new string[](isBase ? 14 : 13);
        fields[0] = "network";
        fields[1] = "beaconSetDeployer";
        fields[2] = "beacons";
        fields[3] = "safe";
        fields[4] = "timelock";
        fields[5] = "orchestrator";
        fields[6] = "authoriser";
        fields[7] = "euAuthoriser";
        fields[8] = "zoltu";
        fields[9] = "upgradeMigration";
        fields[10] = "renameMigration";
        fields[11] = "registryDelegates";
        fields[12] = "tokens";
        if (isBase) {
            fields[13] = "qsep";
        }
        return fields;
    }

    function registryDelegateFields(bool scoped) internal pure returns (string[] memory) {
        string[] memory fields = new string[](scoped ? 5 : 4);
        fields[0] = "registry";
        fields[1] = "account";
        fields[2] = "delegate";
        fields[3] = "unscoped";
        if (scoped) {
            fields[4] = "scope";
        }
        return fields;
    }

    function beaconFields() internal pure returns (string[] memory) {
        string[] memory fields = new string[](5);
        fields[0] = "beacon";
        fields[1] = "codehash";
        fields[2] = "implementation";
        fields[3] = "renamedImplementation";
        fields[4] = "owner";
        return fields;
    }

    function safeFields() internal pure returns (string[] memory) {
        string[] memory fields = new string[](11);
        fields[0] = "address";
        fields[1] = "owners";
        fields[2] = "proxyCodehashes";
        fields[3] = "singletons";
        fields[4] = "singletonCodehashes";
        fields[5] = "version";
        fields[6] = "modules";
        fields[7] = "guard";
        fields[8] = "fallbackHandler";
        fields[9] = "fallbackHandlerCodehash";
        fields[10] = "threshold";
        return fields;
    }

    function timelockFields() internal pure returns (string[] memory) {
        string[] memory fields = new string[](3);
        fields[0] = "address";
        fields[1] = "codehash";
        fields[2] = "minDelay";
        return fields;
    }

    function orchestratorFields() internal pure returns (string[] memory) {
        string[] memory fields = new string[](6);
        fields[0] = "setDeployer";
        fields[1] = "beacon";
        fields[2] = "beaconCodehash";
        fields[3] = "implementation";
        fields[4] = "owner";
        fields[5] = "instance";
        return fields;
    }

    function authoriserFields() internal pure returns (string[] memory) {
        string[] memory fields = new string[](2);
        fields[0] = "address";
        fields[1] = "codehash";
        return fields;
    }

    function tokenFields() internal pure returns (string[] memory) {
        string[] memory fields = new string[](28);
        fields[0] = "underlying";
        fields[1] = "assetId";
        fields[2] = "listingTicker";
        fields[3] = "listingName";
        fields[4] = "region";
        fields[5] = "name";
        fields[6] = "renamedName";
        fields[7] = "symbol";
        fields[8] = "decimals";
        fields[9] = "wrappedTokenVaultName";
        fields[10] = "wrappedTokenVaultRenamedName";
        fields[11] = "wrappedTokenVaultSymbol";
        fields[12] = "wrappedTokenVaultRenamedSymbol";
        fields[13] = "wrappedTokenVaultDecimals";
        fields[14] = "receiptVault";
        fields[15] = "receipt";
        fields[16] = "wrappedTokenVault";
        fields[17] = "receiptVaultReceipt";
        fields[18] = "receiptManager";
        fields[19] = "wrappedTokenVaultAsset";
        fields[20] = "receiptVaultBeacon";
        fields[21] = "receiptBeacon";
        fields[22] = "wrappedTokenVaultBeacon";
        fields[23] = "receiptVaultCodehash";
        fields[24] = "receiptCodehash";
        fields[25] = "wrappedTokenVaultCodehash";
        fields[26] = "owner";
        fields[27] = "authoriser";
        return fields;
    }

    /// The token fields after the metadata.
    function qsepFields() internal pure returns (string[] memory) {
        string[] memory token = tokenFields();
        string[] memory fields = new string[](14);
        for (uint256 i = 0; i < fields.length; i++) {
            fields[i] = token[i + 14];
        }
        return fields;
    }

    function deploymentFields() internal pure returns (string[] memory) {
        string[] memory fields = new string[](3);
        fields[0] = "key";
        fields[1] = "address";
        fields[2] = "codehash";
        return fields;
    }

    function v2ChainFields() internal pure returns (string[] memory) {
        string[] memory fields = new string[](6);
        fields[0] = "network";
        fields[1] = "deployments";
        fields[2] = "beaconSetDeployer";
        fields[3] = "receiptBeacon";
        fields[4] = "receiptVaultBeacon";
        fields[5] = "wrappedTokenVaultBeacon";
        return fields;
    }

    function v2BeaconFields() internal pure returns (string[] memory) {
        string[] memory fields = new string[](3);
        fields[0] = "beacon";
        fields[1] = "implementation";
        fields[2] = "owner";
        return fields;
    }

    function v2Networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibProdDeployV2.deployedNetworks());
    }

    function chain(SupportedNetwork memory network) internal pure returns (string memory) {
        return string.concat(".chains.", vm.toString(network.chainId));
    }

    function v2Chain(SupportedNetwork memory network) internal pure returns (string memory) {
        return string.concat(".v2.", vm.toString(network.chainId));
    }

    function index(string memory at, uint256 i) internal pure returns (string memory) {
        return string.concat(at, "[", vm.toString(i), "]");
    }
}
