// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.30/src/lib/LibSafe.sol";
import {DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployZoltuMechanism} from "rain-deploy-0.1.30/src/lib/LibRainDeployZoltuMechanism.sol";
import {
    BYTECODE_HASH as TIMELOCK_BYTECODE_HASH,
    RUNTIME_CODE as TIMELOCK_RUNTIME_CODE
} from "rain-deploy-0.1.30/src/generated/0_1_18/TimelockController.sol";
import {
    LibExtrospectRegistryBeaconProxy,
    REGISTRY_BEACON_PROXY_PREFIX,
    REGISTRY_BEACON_PROXY_SUFFIX
} from "rain-extrospection-0.1.16/src/lib/LibExtrospectRegistryBeaconProxy.sol";
import {BuildExpectedState} from "../../script/BuildExpectedState.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {RUNTIME_CODE as SUITE_TIMELOCK_RUNTIME_CODE} from "../../src/generated/candidate/StoxGovernanceTimelock.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibEuAuthoriserClone} from "../../src/lib/LibEuAuthoriserClone.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibProdDeployV1} from "../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV2} from "../../src/lib/LibProdDeployV2.sol";
import {LibProdDeployV2BaseOverrides} from "../../src/lib/LibProdDeployV2BaseOverrides.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibReleasedSuites} from "../../src/lib/LibReleasedSuites.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {LibTokenMetadata} from "../../src/lib/LibTokenMetadata.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @notice No `zoltu` row carries the key.
error ZoltuRowMissing(string key);

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
            assertKeys(json, at, chainFields());
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

    function testBeaconsAreTheInUseSetAtTheirExpectedImplementationsOwnedByTheTimelock() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            uint256 id = nets[c].chainId;
            string memory at = chain(nets[c]);
            assertEq(
                vm.parseJsonAddress(json, string.concat(at, ".beaconSetDeployer")),
                LibBeaconInvariants.prodBeaconSetDeployerForChainId(id)
            );
            address[4] memory pinned = LibBeaconInvariants.prodPinnedBeaconsForChainId(id);
            address[4] memory impls = LibBeaconInvariants.prodExpectedImplementationsForChainId(id);
            bytes32[4] memory codehashes = LibBeaconInvariants.prodBeaconCodehashesForChainId(id);
            string memory list = string.concat(at, ".beacons");
            assertFalse(vm.keyExistsJson(json, index(list, pinned.length)));
            for (uint256 i = 0; i < pinned.length; i++) {
                string memory row = index(list, i);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".beacon")), pinned[i]);
                assertEq(vm.parseJsonBytes32(json, string.concat(row, ".codehash")), codehashes[i]);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".implementation")), impls[i]);
                assertEq(
                    vm.parseJsonAddress(json, string.concat(row, ".owner")),
                    LibTimelockInvariants.timelockForChainId(id)
                );
            }
        }
    }

    /// Fixed example from the Ethereum leg: the receipt beacon is read from the beacon set deployer, so its slot is
    /// empty, and it must serve the 0.1.30 receipt.
    function testEthereumReceiptBeaconIsDeployerResolvedAt0_1_30() external {
        string memory json = build.render();
        string memory row = ".chains.1.beacons[0]";
        assertEq(vm.parseJsonAddress(json, string.concat(row, ".beacon")), address(0));
        assertEq(vm.parseJsonAddress(json, string.concat(row, ".implementation")), LibProdDeployV4.STOX_RECEIPT_0_1_30);
        assertEq(
            vm.parseJsonAddress(json, ".chains.1.beaconSetDeployer"),
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1
        );
    }

    function testSafeIsTheChainsSafeWithThePinnedPolicy() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            string memory at = string.concat(chain(nets[i]), ".safe");
            assertEq(
                vm.parseJsonAddress(json, string.concat(at, ".address")),
                LibSafeInvariants.safeForChainId(nets[i].chainId)
            );
            assertEq(
                vm.parseJsonUint(json, string.concat(at, ".threshold")),
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
            );
            address[] memory owners = LibSafeInvariants.expectedOwners();
            string memory list = string.concat(at, ".owners");
            assertFalse(vm.keyExistsJson(json, index(list, owners.length)));
            for (uint256 j = 0; j < owners.length; j++) {
                assertEq(vm.parseJsonAddress(json, index(list, j)), owners[j]);
            }
        }
    }

    /// The accepted proxy, singleton and handler hashes are the hashes of the pinned runtime code, singleton i's
    /// hash at index i, so the dashboard's lock-down check matches `LibSafe.assertLockedDown`.
    function testSafeLockDownIsLibSafesAcceptedCode() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            string memory at = string.concat(chain(nets[i]), ".safe");
            bytes32[] memory proxies = vm.parseJsonBytes32Array(json, string.concat(at, ".proxyCodehashes"));
            assertEq(proxies.length, 2);
            assertEq(proxies[0], keccak256(LibSafe.SAFE_V1_4_1_PROXY_RUNTIME_CODE));
            assertEq(proxies[0], LibSafe.SAFE_V1_4_1_PROXY_CODEHASH);
            assertEq(proxies[1], keccak256(LibSafe.SAFE_V1_3_0_PROXY_RUNTIME_CODE));
            assertEq(proxies[1], LibSafe.SAFE_V1_3_0_PROXY_CODEHASH);

            address[] memory singletons = vm.parseJsonAddressArray(json, string.concat(at, ".singletons"));
            bytes32[] memory singletonHashes = vm.parseJsonBytes32Array(json, string.concat(at, ".singletonCodehashes"));
            assertEq(singletons.length, 2);
            assertEq(singletonHashes.length, 2);
            assertEq(singletons[0], LibSafe.SAFE_V1_4_1_L1_SINGLETON);
            assertEq(singletonHashes[0], keccak256(LibSafe.SAFE_V1_4_1_L1_SINGLETON_RUNTIME_CODE));
            assertEq(singletonHashes[0], LibSafe.SAFE_V1_4_1_L1_SINGLETON_CODEHASH);
            assertEq(singletons[1], LibSafe.SAFE_V1_4_1_L2_SINGLETON);
            assertEq(singletonHashes[1], keccak256(LibSafe.SAFE_V1_4_1_L2_SINGLETON_RUNTIME_CODE));
            assertEq(singletonHashes[1], LibSafe.SAFE_V1_4_1_L2_SINGLETON_CODEHASH);

            assertEq(vm.parseJsonString(json, string.concat(at, ".version")), LibSafe.SAFE_V1_4_1_VERSION);
            assertEq(vm.parseJsonAddressArray(json, string.concat(at, ".modules")).length, 0);
            assertEq(vm.parseJsonAddress(json, string.concat(at, ".guard")), address(0));
            assertEq(
                vm.parseJsonAddress(json, string.concat(at, ".fallbackHandler")),
                LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER
            );
            bytes32 handlerHash = vm.parseJsonBytes32(json, string.concat(at, ".fallbackHandlerCodehash"));
            assertEq(handlerHash, keccak256(LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER_RUNTIME_CODE));
            assertEq(handlerHash, LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER_CODEHASH);
        }
    }

    function testTimelockIsTheChainsPinAtItsMinDelay() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            uint256 id = nets[i].chainId;
            string memory at = string.concat(chain(nets[i]), ".timelock");
            address timelock = vm.parseJsonAddress(json, string.concat(at, ".address"));
            assertEq(timelock, LibTimelockInvariants.timelockForChainId(id));
            assertEq(timelock, LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.safeForChainId(id)));
            assertEq(vm.parseJsonUint(json, string.concat(at, ".minDelay")), LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        }
    }

    /// The suite timelock's address carries the suite's runtime code, every other address the per-Safe code.
    function testTimelockCodehashIsTheSuiteCodeAtTheSuiteAddressAndThePerSafeCodeElsewhere() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        bool sawPerSafe;
        for (uint256 i = 0; i < nets.length; i++) {
            string memory at = string.concat(chain(nets[i]), ".timelock");
            address timelock = vm.parseJsonAddress(json, string.concat(at, ".address"));
            bytes32 codehash = vm.parseJsonBytes32(json, string.concat(at, ".codehash"));
            assertEq(codehash, LibTimelockInvariants.timelockCodehash(timelock));
            if (timelock == LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK) {
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
    /// `UpgradeableBeacon` serving the 0.1.30 orchestrator, and the chain's timelock owns it.
    function testOrchestratorIsThe0_1_30BeaconSetOwnedByTheTimelock() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            string memory at = string.concat(chain(nets[i]), ".orchestrator");
            address setDeployer = vm.parseJsonAddress(json, string.concat(at, ".setDeployer"));
            address beacon = vm.parseJsonAddress(json, string.concat(at, ".beacon"));
            address instance = vm.parseJsonAddress(json, string.concat(at, ".instance"));
            assertEq(setDeployer, LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30);
            assertEq(beacon, LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON);
            assertEq(beacon, vm.computeCreateAddress(setDeployer, 1));
            assertEq(instance, LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);
            assertEq(instance, vm.computeCreateAddress(setDeployer, 2));
            assertEq(
                vm.parseJsonBytes32(json, string.concat(at, ".beaconCodehash")),
                LibBeaconInvariants.UPGRADEABLE_BEACON_CODEHASH_0_1_30
            );
            assertEq(
                vm.parseJsonAddress(json, string.concat(at, ".implementation")),
                LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30
            );
            assertEq(
                vm.parseJsonAddress(json, string.concat(at, ".owner")),
                LibTimelockInvariants.timelockForChainId(nets[i].chainId)
            );
        }
    }

    /// The orchestrator's implementation and set deployer are the released 0.1.30 Zoltu suites on that chain.
    function testOrchestratorCodeIsItsReleasedZoltuSuites() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            string memory at = chain(nets[i]);
            assertEq(
                zoltuAddress(json, at, "stox-orchestrator@0_1_30"),
                vm.parseJsonAddress(json, string.concat(at, ".orchestrator.implementation"))
            );
            assertEq(
                zoltuAddress(json, at, "stox-orchestrator-beacon-set-deployer@0_1_30"),
                vm.parseJsonAddress(json, string.concat(at, ".orchestrator.setDeployer"))
            );
        }
    }

    function testAuthorisersAreTheChainsClonesAtTheCloneCodehash() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            uint256 id = nets[i].chainId;
            string memory at = chain(nets[i]);
            assertEq(
                vm.parseJsonAddress(json, string.concat(at, ".authoriser.address")),
                LibAuthoriserInvariants.authoriserForChainId(id)
            );
            assertEq(
                vm.parseJsonBytes32(json, string.concat(at, ".authoriser.codehash")),
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
            );
            address eu = vm.parseJsonAddress(json, string.concat(at, ".euAuthoriser.address"));
            assertEq(eu, LibAuthoriserInvariants.euAuthoriserForChainId(id));
            assertEq(eu, LibEuAuthoriserClone.cloneDeployedAddress(id));
            assertEq(
                vm.parseJsonBytes32(json, string.concat(at, ".euAuthoriser.codehash")),
                keccak256(LibEuAuthoriserClone.cloneRuntimeCode())
            );
        }
    }

    function testTokensAreTheChainsTableWithRegionRoutedAuthorisers() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            uint256 id = nets[c].chainId;
            TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(id);
            string memory list = string.concat(chain(nets[c]), ".tokens");
            assertFalse(vm.keyExistsJson(json, index(list, tokens.length)));
            for (uint256 i = 0; i < tokens.length; i++) {
                string memory row = index(list, i);
                TokenConfig memory config = LibProdTokenConfig.configOf(tokens[i].underlying);
                assertEq(vm.parseJsonString(json, string.concat(row, ".underlying")), tokens[i].underlying);
                assertEq(vm.parseJsonString(json, string.concat(row, ".name")), config.name);
                assertEq(vm.parseJsonString(json, string.concat(row, ".symbol")), config.symbol);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".receiptVault")), tokens[i].receiptVault);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".receipt")), tokens[i].receipt);
                assertEq(
                    vm.parseJsonAddress(json, string.concat(row, ".wrappedTokenVault")), tokens[i].wrappedTokenVault
                );
                assertEq(
                    vm.parseJsonAddress(json, string.concat(row, ".owner")),
                    LibTimelockInvariants.timelockForChainId(id)
                );
                address expected = config.region == Region.EU
                    ? LibAuthoriserInvariants.euAuthoriserForChainId(id)
                    : LibAuthoriserInvariants.authoriserForChainId(id);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".authoriser")), expected);
            }
        }
    }

    /// Fixed examples on Base: tMC is the EU token, on the EU clone; tMSTR is US, on the V4 clone.
    function testBaseMcIsOnTheEuCloneAndMstrOnTheV4Clone() external {
        string memory json = build.render();
        string memory list = ".chains.8453.tokens";
        uint256 n = LibTokenInvariants.productionTokensBase().length;
        bool sawMc;
        bool sawMstr;
        for (uint256 i = 0; i < n; i++) {
            string memory row = index(list, i);
            bytes32 underlying = keccak256(bytes(vm.parseJsonString(json, string.concat(row, ".underlying"))));
            address authoriser = vm.parseJsonAddress(json, string.concat(row, ".authoriser"));
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

    /// The unprefixed fields are the initialized metadata, the `renamed` fields the metadata once the rename batch has
    /// run, which renames only its leading rows; each set is one consistent state of the vault and wrapper.
    function testTokenMetadataIsTheInitializedAndRenamedStates() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(nets[c].chainId);
            string memory list = string.concat(chain(nets[c]), ".tokens");
            for (uint256 i = 0; i < tokens.length; i++) {
                assertTokenMetadata(
                    json,
                    index(list, i),
                    LibProdTokenConfig.configOf(tokens[i].underlying),
                    LibUnderlyingNamingRollout.renamesRow(i)
                );
            }
        }
    }

    function assertTokenMetadata(string memory json, string memory row, TokenConfig memory config, bool renames)
        internal
        pure
    {
        string memory symbol = field(json, row, "symbol");
        assertMetadataState(
            config,
            false,
            field(json, row, "name"),
            symbol,
            field(json, row, "wrappedTokenVaultName"),
            field(json, row, "wrappedTokenVaultSymbol")
        );
        string memory renamedName = field(json, row, "renamedName");
        assertMetadataState(
            config,
            renames,
            renamedName,
            symbol,
            field(json, row, "wrappedTokenVaultRenamedName"),
            field(json, row, "wrappedTokenVaultRenamedSymbol")
        );
        assertEq(LibTokenMetadata.vaultRenamed(config, renamedName), renames);
    }

    function assertMetadataState(
        TokenConfig memory config,
        bool renamed,
        string memory name,
        string memory symbol,
        string memory wrappedName,
        string memory wrappedSymbol
    ) internal pure {
        assertEq(name, LibTokenMetadata.vaultName(config, renamed));
        assertEq(wrappedName, LibTokenMetadata.wrappedName(config, renamed));
        assertEq(wrappedSymbol, LibTokenMetadata.wrappedSymbol(config, renamed));
        assertTrue(LibTokenMetadata.consistent(config, name, symbol, wrappedName, wrappedSymbol));
    }

    function testTokenDecimalsAreTheVaultAndWrapperDecimals() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            string memory list = string.concat(chain(nets[c]), ".tokens");
            uint256 n = LibTokenInvariants.productionTokensForChainId(nets[c].chainId).length;
            for (uint256 i = 0; i < n; i++) {
                string memory row = index(list, i);
                assertEq(
                    vm.parseJsonUint(json, string.concat(row, ".decimals")), LibTokenMetadata.RECEIPT_VAULT_DECIMALS
                );
                assertEq(
                    vm.parseJsonUint(json, string.concat(row, ".wrappedTokenVaultDecimals")),
                    LibTokenMetadata.WRAPPED_TOKEN_VAULT_DECIMALS
                );
            }
        }
    }

    function testTokenVaultReceiptAndWrapperAssetAreTheRowsOwnLegs() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(nets[c].chainId);
            string memory list = string.concat(chain(nets[c]), ".tokens");
            for (uint256 i = 0; i < tokens.length; i++) {
                string memory row = index(list, i);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".receiptVaultReceipt")), tokens[i].receipt);
                assertEq(
                    vm.parseJsonAddress(json, string.concat(row, ".wrappedTokenVaultAsset")), tokens[i].receiptVault
                );
            }
        }
    }

    /// Each leg's beacon is the chain's beacon row for that leg, `address(0)` where the set deployer resolves it.
    function testTokenLegBeaconsAreTheChainsBeaconRows() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            uint256 id = nets[c].chainId;
            string memory at = chain(nets[c]);
            address[4] memory pinned = LibBeaconInvariants.prodPinnedBeaconsForChainId(id);
            address receiptBeacon = beaconRow(json, at, LibBeaconInvariants.RECEIPT_BEACON_INDEX);
            address vaultBeacon = beaconRow(json, at, LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX);
            address wrapperBeacon = beaconRow(json, at, LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX);
            assertEq(receiptBeacon, pinned[LibBeaconInvariants.RECEIPT_BEACON_INDEX]);
            assertEq(vaultBeacon, pinned[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]);
            assertEq(wrapperBeacon, pinned[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX]);
            string memory list = string.concat(at, ".tokens");
            uint256 n = LibTokenInvariants.productionTokensForChainId(id).length;
            for (uint256 i = 0; i < n; i++) {
                string memory row = index(list, i);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".receiptBeacon")), receiptBeacon);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".receiptVaultBeacon")), vaultBeacon);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".wrappedTokenVaultBeacon")), wrapperBeacon);
            }
        }
    }

    /// Base's token proxies are the V1 build, pinned by codehash.
    function testBaseTokenLegCodehashesAreTheV1ProxyPins() external {
        string memory json = build.render();
        string memory list = ".chains.8453.tokens";
        uint256 n = LibTokenInvariants.productionTokensBase().length;
        for (uint256 i = 0; i < n; i++) {
            string memory row = index(list, i);
            assertEq(
                vm.parseJsonBytes32(json, string.concat(row, ".receiptCodehash")),
                LibProdDeployV1.PROD_STOX_RECEIPT_PROXY_BASE_CODEHASH_V1
            );
            assertEq(
                vm.parseJsonBytes32(json, string.concat(row, ".receiptVaultCodehash")),
                LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_PROXY_BASE_CODEHASH_V1
            );
            assertEq(
                vm.parseJsonBytes32(json, string.concat(row, ".wrappedTokenVaultCodehash")),
                LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_PROXY_BASE_CODEHASH_V1
            );
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
        bytes32 wrapperHash =
            registryBeaconProxyCodehash(beaconRow(json, at, LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX));
        string memory list = string.concat(at, ".tokens");
        uint256 n = LibTokenInvariants.productionTokensForChainId(network.chainId).length;
        for (uint256 i = 0; i < n; i++) {
            string memory row = index(list, i);
            assertEq(vm.parseJsonBytes32(json, string.concat(row, ".receiptCodehash")), receiptHash);
            assertEq(vm.parseJsonBytes32(json, string.concat(row, ".receiptVaultCodehash")), vaultHash);
            assertEq(vm.parseJsonBytes32(json, string.concat(row, ".wrappedTokenVaultCodehash")), wrapperHash);
        }
    }

    /// The rename migration is the id of the script that executes the rename batch.
    function testRenameMigrationIsTheExecuteUnderlyingNamingScript() external {
        string memory json = build.render();
        string memory script = "script/20261021-execute-underlying-naming.s.sol";
        assertTrue(vm.exists(script));
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            bytes32 id = vm.parseJsonBytes32(json, string.concat(chain(nets[c]), ".renameMigration"));
            assertEq(id, LibStoxMigrations.EXECUTE_UNDERLYING_NAMING);
            assertEq(id, keccak256(bytes(script)));
        }
    }

    function testV2IsTheV2NetworksKeyedByChainId() external {
        string memory json = build.render();
        SupportedNetwork[] memory v2 = v2Networks();
        assertEq(vm.parseJsonKeys(json, ".v2").length, v2.length);
        uint256[] memory ids = new uint256[](5);
        ids[0] = 42161;
        ids[1] = 8453;
        ids[2] = 84532;
        ids[3] = 14;
        ids[4] = 137;
        for (uint256 i = 0; i < v2.length; i++) {
            assertEq(v2[i].chainId, ids[i]);
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
            string memory list = string.concat(v2Chain(v2[c]), ".deployments");
            assertFalse(vm.keyExistsJson(json, index(list, keys.length)));
            for (uint256 i = 0; i < keys.length; i++) {
                string memory row = index(list, i);
                assertEq(vm.parseJsonString(json, string.concat(row, ".key")), keys[i]);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".address")), addresses[i]);
                assertEq(vm.parseJsonBytes32(json, string.concat(row, ".codehash")), codehashes[i]);
            }
        }
    }

    /// The receipt and receipt-vault beacons are resolved from the deployed set deployer and serve the V2 receipt and
    /// vault from the V2 owner, except on Base, which carries its overrides; the wrapper beacon is the deployed one.
    function testV2BeaconsAreTheSetDeployersWithBaseOverrides() external {
        string memory json = build.render();
        SupportedNetwork[] memory v2 = v2Networks();
        bool sawBase;
        for (uint256 c = 0; c < v2.length; c++) {
            string memory at = v2Chain(v2[c]);
            bool isBase = v2[c].chainId == LibSafeInvariants.BASE_CHAIN_ID;
            sawBase = sawBase || isBase;
            address setDeployer = vm.parseJsonAddress(json, string.concat(at, ".beaconSetDeployer"));
            assertEq(setDeployer, LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER);
            assertEq(setDeployer, vm.parseJsonAddress(json, string.concat(at, ".deployments[5].address")));
            assertV2Beacon(
                json,
                string.concat(at, ".receiptBeacon"),
                address(0),
                isBase ? LibProdDeployV2BaseOverrides.RECEIPT_BEACON_IMPLEMENTATION : LibProdDeployV2.STOX_RECEIPT,
                isBase ? LibProdDeployV2BaseOverrides.RECEIPT_BEACON_OWNER : LibProdDeployV2.BEACON_INITIAL_OWNER
            );
            assertV2Beacon(
                json,
                string.concat(at, ".receiptVaultBeacon"),
                address(0),
                isBase ? LibProdDeployV2BaseOverrides.VAULT_BEACON_IMPLEMENTATION : LibProdDeployV2.STOX_RECEIPT_VAULT,
                isBase ? LibProdDeployV2BaseOverrides.VAULT_BEACON_OWNER : LibProdDeployV2.BEACON_INITIAL_OWNER
            );
            assertV2Beacon(
                json,
                string.concat(at, ".wrappedTokenVaultBeacon"),
                vm.parseJsonAddress(json, string.concat(at, ".deployments[4].address")),
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT,
                LibProdDeployV2.BEACON_INITIAL_OWNER
            );
            assertEq(
                vm.parseJsonAddress(json, string.concat(at, ".wrappedTokenVaultBeacon.beacon")),
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON
            );
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
            string memory list = string.concat(chain(nets[c]), ".zoltu");
            assertFalse(vm.keyExistsJson(json, index(list, suites.length)));
            for (uint256 i = 0; i < suites.length; i++) {
                string memory row = index(list, i);
                assertEq(vm.parseJsonString(json, string.concat(row, ".key")), suites[i].suite);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".address")), suites[i].storedDeployedAddress);
                bytes32 codehash = vm.parseJsonBytes32(json, string.concat(row, ".codehash"));
                assertEq(codehash, suites[i].storedBytecodeHash);
                assertEq(codehash, keccak256(suites[i].storedRuntimeCode));
            }
        }
    }

    function testRunWritesTheRender() external {
        vm.removeFile("expected-state.json");
        build.run();
        assertEq(keccak256(vm.parseJson(vm.readFile("expected-state.json"))), keccak256(vm.parseJson(build.render())));
    }

    function expectedZoltu(SupportedNetwork memory network) internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory released = LibReleasedSuites.releasedSuites();
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

    function zoltuAddress(string memory json, string memory at, string memory key) internal view returns (address) {
        string memory list = string.concat(at, ".zoltu");
        for (uint256 i = 0; vm.keyExistsJson(json, index(list, i)); i++) {
            string memory row = index(list, i);
            if (keccak256(bytes(vm.parseJsonString(json, string.concat(row, ".key")))) == keccak256(bytes(key))) {
                return vm.parseJsonAddress(json, string.concat(row, ".address"));
            }
        }
        revert ZoltuRowMissing(key);
    }

    function assertKeys(string memory json, string memory at, string[] memory expected) internal view {
        assertEq(vm.parseJsonKeys(json, bytes(at).length == 0 ? "$" : at).length, expected.length, at);
        for (uint256 i = 0; i < expected.length; i++) {
            assertTrue(vm.keyExistsJson(json, string.concat(at, ".", expected[i])), string.concat(at, ".", expected[i]));
        }
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

    function field(string memory json, string memory row, string memory key) internal pure returns (string memory) {
        return vm.parseJsonString(json, string.concat(row, ".", key));
    }

    function beaconRow(string memory json, string memory at, uint256 i) internal pure returns (address) {
        return vm.parseJsonAddress(json, string.concat(index(string.concat(at, ".beacons"), i), ".beacon"));
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

    function assertV2Beacon(string memory json, string memory at, address beacon, address implementation, address owner)
        internal
        pure
    {
        assertEq(vm.parseJsonAddress(json, string.concat(at, ".beacon")), beacon);
        assertEq(vm.parseJsonAddress(json, string.concat(at, ".implementation")), implementation);
        assertEq(vm.parseJsonAddress(json, string.concat(at, ".owner")), owner);
    }

    function chainFields() internal pure returns (string[] memory) {
        string[] memory fields = new string[](11);
        fields[0] = "network";
        fields[1] = "beaconSetDeployer";
        fields[2] = "beacons";
        fields[3] = "safe";
        fields[4] = "timelock";
        fields[5] = "orchestrator";
        fields[6] = "authoriser";
        fields[7] = "euAuthoriser";
        fields[8] = "zoltu";
        fields[9] = "renameMigration";
        fields[10] = "tokens";
        return fields;
    }

    function beaconFields() internal pure returns (string[] memory) {
        string[] memory fields = new string[](4);
        fields[0] = "beacon";
        fields[1] = "codehash";
        fields[2] = "implementation";
        fields[3] = "owner";
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
        string[] memory fields = new string[](23);
        fields[0] = "underlying";
        fields[1] = "name";
        fields[2] = "renamedName";
        fields[3] = "symbol";
        fields[4] = "decimals";
        fields[5] = "wrappedTokenVaultName";
        fields[6] = "wrappedTokenVaultRenamedName";
        fields[7] = "wrappedTokenVaultSymbol";
        fields[8] = "wrappedTokenVaultRenamedSymbol";
        fields[9] = "wrappedTokenVaultDecimals";
        fields[10] = "receiptVault";
        fields[11] = "receipt";
        fields[12] = "wrappedTokenVault";
        fields[13] = "receiptVaultReceipt";
        fields[14] = "wrappedTokenVaultAsset";
        fields[15] = "receiptVaultBeacon";
        fields[16] = "receiptBeacon";
        fields[17] = "wrappedTokenVaultBeacon";
        fields[18] = "receiptVaultCodehash";
        fields[19] = "receiptCodehash";
        fields[20] = "wrappedTokenVaultCodehash";
        fields[21] = "owner";
        fields[22] = "authoriser";
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
        string[] memory networkNames = new string[](5);
        networkNames[0] = LibRainDeploy.ARBITRUM_ONE;
        networkNames[1] = LibRainDeploy.BASE;
        networkNames[2] = LibRainDeploy.BASE_SEPOLIA;
        networkNames[3] = LibRainDeploy.FLARE;
        networkNames[4] = LibRainDeploy.POLYGON;
        return LibRainDeploy.declaredNetworkConfigs(networkNames);
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
