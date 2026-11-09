// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V8_ADDRESS
} from "rain-factory-deploy-0.2.6/src/generated/0_2_5/CloneFactory.sol";
import {ICloneableFactoryV7} from "rain-factory-0.2.10/src/interface/ICloneableFactoryV7.sol";
import {
    LibRainDeployCloneMechanism,
    REGISTRY_BEACON_PROXY_MECHANISM
} from "rain-factory-0.2.10/src/lib/LibRainDeployCloneMechanism.sol";
import {RegistryBeaconProxyTarget} from "rain-factory-0.2.10/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {IAuthorizeV1} from "rain-vats-0.2.18/src/interface/IAuthorizeV1.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {LibProdDeployV4 as V4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LibTestTokenEnvironment} from "../../lib/LibTestTokenEnvironment.sol";

/// @title StoxDeploySuitesTestTokenSuitesTest
/// @notice The US and EU test tokens and their wrappers are registry beacon proxy suites that land at their stored
/// addresses on every network this repo deploys to.
contract StoxDeploySuitesTestTokenSuitesTest is Test, StoxDeploySuites {
    address internal constant US_OWNER = address(uint160(uint256(keccak256("st0x.test.test-token-suites.us-owner"))));
    address internal constant EU_OWNER = address(uint160(uint256(keccak256("st0x.test.test-token-suites.eu-owner"))));
    address internal constant DEPLOYER = address(uint160(uint256(keccak256("st0x.test.test-token-suites.deployer"))));
    address internal constant BEACON_OWNER =
        address(uint160(uint256(keccak256("st0x.test.test-token-suites.beacon-owner"))));

    struct ExpectedTestToken {
        string key;
        string name;
        string symbol;
        bool us;
    }

    function expectedTestTokens() internal pure returns (ExpectedTestToken[] memory) {
        ExpectedTestToken[] memory tokens = new ExpectedTestToken[](2);
        tokens[0] = ExpectedTestToken({key: "stox-token-tustest", name: "US Test ST0x", symbol: "tUSTEST", us: true});
        tokens[1] = ExpectedTestToken({key: "stox-token-teutest", name: "EU Test ST0x", symbol: "tEUTEST", us: false});
        return tokens;
    }

    function wrapperKey(ExpectedTestToken memory token) internal pure returns (string memory) {
        return string.concat(token.key, "-wrapper");
    }

    function targetOf(DeploySuite memory suite) internal pure returns (RegistryBeaconProxyTarget memory) {
        return LibRainDeployCloneMechanism.registryBeaconProxyTarget(suite);
    }

    function dependencyCodeHash(DeploySuite memory suite, address dependency) internal pure returns (bytes32) {
        uint256 matches = 0;
        bytes32 codeHash;
        for (uint256 i = 0; i < suite.dependencies.length; i++) {
            if (suite.dependencies[i].deployedAddress == dependency) {
                matches++;
                codeHash = keccak256(suite.dependencies[i].runtimeCode);
            }
        }
        assertEq(matches, 1, suite.suite);
        return codeHash;
    }

    function testEachTestTokenIsARegistryBeaconProxyOverTheVaultBeacon() external view {
        DeployDeclaration memory declared = declaration();
        ExpectedTestToken[] memory tokens = expectedTestTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            DeploySuite memory suite = suiteByName(declared, tokens[i].key);
            assertEq(mechanismIdOf(suite), REGISTRY_BEACON_PROXY_MECHANISM, tokens[i].key);
            RegistryBeaconProxyTarget memory target = targetOf(suite);
            assertEq(target.factory, CLONE_FACTORY_V8_ADDRESS, tokens[i].key);
            assertEq(target.registry, CONFIG_REGISTRY_ADDRESS, tokens[i].key);
            assertEq(target.authority, LibRegistryAuthority.ROOT_AUTHORITY, tokens[i].key);
            assertEq(target.beaconName, LibStoxConfig.VAULT_BEACON_NAME, tokens[i].key);
            assertEq(target.beacon, V4.STOX_RECEIPT_VAULT_BEACON_CANDIDATE, tokens[i].key);
        }
    }

    function testEachTestTokenWrapperIsARegistryBeaconProxyOverTheWrapperBeaconWrappingItsToken() external view {
        DeployDeclaration memory declared = declaration();
        ExpectedTestToken[] memory tokens = expectedTestTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            DeploySuite memory token = suiteByName(declared, tokens[i].key);
            DeploySuite memory wrapper = suiteByName(declared, wrapperKey(tokens[i]));
            assertEq(mechanismIdOf(wrapper), REGISTRY_BEACON_PROXY_MECHANISM, wrapper.suite);
            RegistryBeaconProxyTarget memory target = targetOf(wrapper);
            assertEq(target.factory, CLONE_FACTORY_V8_ADDRESS, wrapper.suite);
            assertEq(target.registry, CONFIG_REGISTRY_ADDRESS, wrapper.suite);
            assertEq(target.authority, LibRegistryAuthority.ROOT_AUTHORITY, wrapper.suite);
            assertEq(target.beaconName, LibStoxConfig.WRAPPER_BEACON_NAME, wrapper.suite);
            assertEq(target.beacon, V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE, wrapper.suite);
            assertEq(target.data, abi.encode(token.storedDeployedAddress), wrapper.suite);
            assertTrue(wrapper.storedDeployedAddress != token.storedDeployedAddress, wrapper.suite);
        }
    }

    function testEachTestTokenWrapperDependsOnItsTokenAndTheWrapperBeaconSuite() external view {
        DeployDeclaration memory declared = declaration();
        (DeploySuite memory beacon, bool found) = candidateOf(declared, WRAPPED_TOKEN_VAULT_BEACON);
        assertTrue(found, WRAPPED_TOKEN_VAULT_BEACON);
        assertEq(beacon.storedDeployedAddress, V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE, beacon.suite);
        ExpectedTestToken[] memory tokens = expectedTestTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            DeploySuite memory token = suiteByName(declared, tokens[i].key);
            DeploySuite memory wrapper = suiteByName(declared, wrapperKey(tokens[i]));
            assertEq(dependencyCodeHash(wrapper, token.storedDeployedAddress), token.storedBytecodeHash, wrapper.suite);
            assertEq(
                dependencyCodeHash(wrapper, beacon.storedDeployedAddress), beacon.storedBytecodeHash, wrapper.suite
            );
        }
    }

    /// Every registry beacon proxy suite over the wrapper beacon is one of the test-token wrappers.
    function testTheTestTokenWrappersAreTheOnlyWrapperSuites() external view {
        DeploySuite[] memory suites = allSuites(declaration());
        ExpectedTestToken[] memory tokens = expectedTestTokens();
        uint256 wrappers = 0;
        for (uint256 i = 0; i < suites.length; i++) {
            if (mechanismIdOf(suites[i]) != REGISTRY_BEACON_PROXY_MECHANISM) {
                continue;
            }
            if (targetOf(suites[i]).beaconName != LibStoxConfig.WRAPPER_BEACON_NAME) {
                continue;
            }
            wrappers++;
            uint256 matches = 0;
            for (uint256 j = 0; j < tokens.length; j++) {
                if (keccak256(bytes(suites[i].suite)) == keccak256(bytes(wrapperKey(tokens[j])))) {
                    matches++;
                }
            }
            assertEq(matches, 1, suites[i].suite);
        }
        assertEq(wrappers, tokens.length, "one wrapper per test token");
    }

    function deployTestTokenEnvironment() internal returns (IAuthorizeV1, IAuthorizeV1) {
        (IAuthorizeV1 usAuthorizer, IAuthorizeV1 euAuthorizer) =
            LibTestTokenEnvironment.deploy(vm, BEACON_OWNER, US_OWNER, EU_OWNER);
        address wrapperBeacon = LibRainDeploy.deployZoltu(V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CREATION_CODE_CANDIDATE);
        assertEq(wrapperBeacon, V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE, "wrapper beacon");
        LibTestDeploy.bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.WRAPPER_BEACON_NAME,
            "address",
            abi.encode(wrapperBeacon)
        );
        return (usAuthorizer, euAuthorizer);
    }

    function deploySuite(DeployDeclaration memory declared, DeploySuite memory suite, SupportedNetwork memory network)
        internal
        returns (address)
    {
        address deployed =
            deployStep(declared, suite)(vm, network.name, DEPLOYER, deployStepData(declared, suite, network.chainId));
        assertEq(deployed, suite.storedDeployedAddress, string.concat(suite.suite, " on ", network.name));
        assertEq(deployed.code, suite.storedRuntimeCode, string.concat(suite.suite, " on ", network.name));
        assertEq(deployed.codehash, suite.storedBytecodeHash, string.concat(suite.suite, " on ", network.name));
        return deployed;
    }

    function assertToken(
        StoxReceiptVault token,
        ExpectedTestToken memory expected,
        IAuthorizeV1 authorizer,
        string memory network
    ) internal view {
        string memory label = string.concat(expected.key, " on ", network);
        assertEq(token.name(), expected.name, label);
        assertEq(token.symbol(), expected.symbol, label);
        assertEq(token.owner(), expected.us ? US_OWNER : EU_OWNER, label);
        assertEq(address(token.authorizer()), address(authorizer), label);
        address receipt = address(token.receipt());
        assertEq(
            receipt,
            ICloneableFactoryV7(CLONE_FACTORY_V8_ADDRESS)
                .predictRegistryBeaconProxyAddress(
                    CONFIG_REGISTRY_ADDRESS,
                    LibRegistryAuthority.ROOT_AUTHORITY,
                    LibStoxConfig.RECEIPT_BEACON_NAME,
                    abi.encode(address(token)),
                    bytes32(0)
                ),
            label
        );
        assertEq(token.receipt().manager(), address(token), label);
    }

    function testEachTestTokenAndWrapperLandAtTheirStoredAddressesOnEveryNetwork() external {
        (IAuthorizeV1 usAuthorizer, IAuthorizeV1 euAuthorizer) = deployTestTokenEnvironment();
        DeployDeclaration memory declared = declaration();
        SupportedNetwork[] memory networks = LibRainDeploy.declaredNetworkConfigs(declared.deployNetworks);
        assertTrue(networks.length > 0, "networks");
        ExpectedTestToken[] memory tokens = expectedTestTokens();
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 preDeploy = vm.snapshotState();
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < tokens.length; j++) {
                address token = deploySuite(declared, suiteByName(declared, tokens[j].key), networks[i]);
                assertToken(
                    StoxReceiptVault(payable(token)),
                    tokens[j],
                    tokens[j].us ? usAuthorizer : euAuthorizer,
                    networks[i].name
                );
                address wrapper = deploySuite(declared, suiteByName(declared, wrapperKey(tokens[j])), networks[i]);
                assertEq(
                    StoxWrappedTokenVault(wrapper).asset(),
                    token,
                    string.concat(wrapperKey(tokens[j]), " on ", networks[i].name)
                );
            }
            assertTrue(vm.revertToState(preDeploy), networks[i].name);
        }
    }
}
