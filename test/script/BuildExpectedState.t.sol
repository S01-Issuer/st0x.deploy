// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.29/src/lib/LibSafe.sol";
import {DeploySuite} from "rain-deploy-0.1.29/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployZoltuMechanism} from "rain-deploy-0.1.29/src/lib/LibRainDeployZoltuMechanism.sol";
import {
    BYTECODE_HASH as TIMELOCK_BYTECODE_HASH,
    RUNTIME_CODE as TIMELOCK_RUNTIME_CODE
} from "rain-deploy-0.1.29/src/generated/0_1_18/TimelockController.sol";
import {BuildExpectedState} from "../../script/BuildExpectedState.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibEuAuthoriserClone} from "../../src/lib/LibEuAuthoriserClone.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibReleasedSuites} from "../../src/lib/LibReleasedSuites.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";

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
        string[] memory root = new string[](2);
        root[0] = "version";
        root[1] = "chains";
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
            assertRowKeys(json, string.concat(at, ".zoltu"), expectedZoltu(nets[c]).length, zoltuFields());
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

    function testTimelockIsTheChainsPinAtTheFrozenCodeAndMinDelay() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            uint256 id = nets[i].chainId;
            string memory at = string.concat(chain(nets[i]), ".timelock");
            address timelock = vm.parseJsonAddress(json, string.concat(at, ".address"));
            assertEq(timelock, LibTimelockInvariants.timelockForChainId(id));
            assertEq(timelock, LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.safeForChainId(id)));
            bytes32 codehash = vm.parseJsonBytes32(json, string.concat(at, ".codehash"));
            assertEq(codehash, TIMELOCK_BYTECODE_HASH);
            assertEq(codehash, keccak256(TIMELOCK_RUNTIME_CODE));
            assertEq(vm.parseJsonUint(json, string.concat(at, ".minDelay")), LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        }
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
                TokenConfig memory config = configOf(tokens[i].underlying);
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
        revert(string.concat("no zoltu row ", key));
    }

    function configOf(string memory underlying) internal pure returns (TokenConfig memory) {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 i = 0; i < configs.length; i++) {
            if (keccak256(bytes(configs[i].underlying)) == keccak256(bytes(underlying))) {
                return configs[i];
            }
        }
        revert("no config");
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

    function chainFields() internal pure returns (string[] memory fields) {
        fields = new string[](10);
        fields[0] = "network";
        fields[1] = "beaconSetDeployer";
        fields[2] = "beacons";
        fields[3] = "safe";
        fields[4] = "timelock";
        fields[5] = "orchestrator";
        fields[6] = "authoriser";
        fields[7] = "euAuthoriser";
        fields[8] = "zoltu";
        fields[9] = "tokens";
    }

    function beaconFields() internal pure returns (string[] memory fields) {
        fields = new string[](4);
        fields[0] = "beacon";
        fields[1] = "codehash";
        fields[2] = "implementation";
        fields[3] = "owner";
    }

    function safeFields() internal pure returns (string[] memory fields) {
        fields = new string[](11);
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
    }

    function timelockFields() internal pure returns (string[] memory fields) {
        fields = new string[](3);
        fields[0] = "address";
        fields[1] = "codehash";
        fields[2] = "minDelay";
    }

    function orchestratorFields() internal pure returns (string[] memory fields) {
        fields = new string[](6);
        fields[0] = "setDeployer";
        fields[1] = "beacon";
        fields[2] = "beaconCodehash";
        fields[3] = "implementation";
        fields[4] = "owner";
        fields[5] = "instance";
    }

    function authoriserFields() internal pure returns (string[] memory fields) {
        fields = new string[](2);
        fields[0] = "address";
        fields[1] = "codehash";
    }

    function tokenFields() internal pure returns (string[] memory fields) {
        fields = new string[](8);
        fields[0] = "underlying";
        fields[1] = "name";
        fields[2] = "symbol";
        fields[3] = "receiptVault";
        fields[4] = "receipt";
        fields[5] = "wrappedTokenVault";
        fields[6] = "owner";
        fields[7] = "authoriser";
    }

    function zoltuFields() internal pure returns (string[] memory fields) {
        fields = new string[](3);
        fields[0] = "key";
        fields[1] = "address";
        fields[2] = "codehash";
    }

    function chain(SupportedNetwork memory network) internal pure returns (string memory) {
        return string.concat(".chains.", vm.toString(network.chainId));
    }

    function index(string memory at, uint256 i) internal pure returns (string memory) {
        return string.concat(at, "[", vm.toString(i), "]");
    }
}
