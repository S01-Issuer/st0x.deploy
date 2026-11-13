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
} from "rain-factory-deploy-0.2.8/src/generated/0_2_5/CloneFactory.sol";
import {ICloneableFactoryV7} from "rain-factory-0.2.11/src/interface/ICloneableFactoryV7.sol";
import {
    LibRainDeployCloneMechanism,
    REGISTRY_BEACON_PROXY_MECHANISM
} from "rain-factory-0.2.11/src/lib/LibRainDeployCloneMechanism.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyParams
} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {IAuthorizeV1} from "rain-vats-0.2.20/src/interface/IAuthorizeV1.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxTokenConfigV1} from "../../../src/interface/IStoxTokenConfigV1.sol";
import {LibProdDeployV4 as V4} from "../../../src/generated/LibProdDeployV4.sol";
import {Region, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenParams} from "../../../src/lib/LibProdTokenParams.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {ST0X_NAME_SUFFIX} from "../../../src/lib/LibUnderlying.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LibTestTokenEnvironment} from "../../lib/LibTestTokenEnvironment.sol";
import {LibTestTokenRows} from "../../lib/LibTestTokenRows.sol";

/// @title StoxDeploySuitesTokenSuitesTest
/// @notice Every token row, production and test alike, is exactly one declared token suite and one declared wrapper
/// suite, keyed by its symbol, deploying the params its listing facts make, and landing at its stored address with its
/// stored runtime code on every deployment network.
contract StoxDeploySuitesTokenSuitesTest is Test, StoxDeploySuites {
    address internal constant US_OWNER = address(uint160(uint256(keccak256("st0x.test.token-suites.us-owner"))));
    address internal constant EU_OWNER = address(uint160(uint256(keccak256("st0x.test.token-suites.eu-owner"))));
    address internal constant DEPLOYER = address(uint160(uint256(keccak256("st0x.test.token-suites.deployer"))));
    address internal constant TIMELOCK = address(uint160(uint256(keccak256("st0x.test.token-suites.timelock"))));

    /// Released and candidate alike, so a suite declared as a release is counted.
    function declaredSuitesWhere(
        DeployDeclaration memory declared,
        function(DeploySuite memory) internal pure returns (bool) keep
    ) internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory found = new DeploySuite[](declared.released.length + declared.candidates.length);
        uint256 count = 0;
        for (uint256 i = 0; i < declared.released.length; i++) {
            if (keep(declared.released[i])) {
                found[count++] = declared.released[i];
            }
        }
        for (uint256 i = 0; i < declared.candidates.length; i++) {
            if (keep(declared.candidates[i].snapshot)) {
                found[count++] = declared.candidates[i].snapshot;
            }
        }
        assembly ("memory-safe") {
            mstore(found, count)
        }
        return found;
    }

    function isWrapperSuite(DeploySuite memory suite) internal pure returns (bool) {
        return mechanismIdOf(suite) == REGISTRY_BEACON_PROXY_MECHANISM
            && LibRainDeployCloneMechanism.registryBeaconProxyParams(suite).beaconName
                == LibStoxConfig.WRAPPER_BEACON_NAME;
    }

    /// Every registry beacon proxy suite but the orchestrator instance and the wrappers.
    function isTokenSuite(DeploySuite memory suite) internal pure returns (bool) {
        return mechanismIdOf(suite) == REGISTRY_BEACON_PROXY_MECHANISM
            && keccak256(bytes(suite.suite)) != keccak256(bytes(ORCHESTRATOR_PROXY)) && !isWrapperSuite(suite);
    }

    function suiteNamed(DeploySuite[] memory all, string memory key) internal pure returns (DeploySuite memory) {
        uint256 index = suiteIndex(all, key);
        assertLt(index, all.length, key);
        return all[index];
    }

    function tokenKey(TokenConfig memory config) internal pure returns (string memory) {
        return string.concat(TOKEN_PREFIX, lowercase(config.symbol));
    }

    /// @return The index of the one config whose listing facts `suite`'s token params carry; a wrapper suite's
    /// config is its token's.
    function configIndexOf(TokenConfig[] memory configs, DeploySuite memory suite) internal pure returns (uint256) {
        RegistryBeaconProxyParams memory params = LibRainDeployCloneMechanism.registryBeaconProxyParams(suite);
        bool wrapper = isWrapperSuite(suite);
        RegistryBeaconProxyParams[] memory tokens;
        StoxTokenConfigV1 memory listed;
        if (wrapper) {
            tokens = LibProdTokenParams.tokenParams(configs);
        } else {
            (, listed) = abi.decode(params.data, (bytes32, StoxTokenConfigV1));
        }
        uint256 matches = 0;
        uint256 index = 0;
        for (uint256 j = 0; j < configs.length; j++) {
            bool isRow = wrapper
                ? keccak256(params.data)
                    == keccak256(abi.encode(LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(tokens[j])))
                : keccak256(bytes(listed.assetId)) == keccak256(bytes(configs[j].assetId))
                    && keccak256(bytes(listed.listingTicker)) == keccak256(bytes(configs[j].listingTicker))
                    && keccak256(bytes(listed.listingName)) == keccak256(bytes(configs[j].listingName))
                    && listed.region == configs[j].region;
            if (isRow) {
                matches++;
                index = j;
            }
        }
        assertEq(matches, 1, suite.suite);
        return index;
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

    function assertOneSuitePerRow(DeploySuite[] memory suites) internal pure {
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        assertEq(suites.length, configs.length, "one suite per row");
        uint256[] memory hits = new uint256[](configs.length);
        for (uint256 i = 0; i < suites.length; i++) {
            hits[configIndexOf(configs, suites[i])]++;
        }
        for (uint256 j = 0; j < configs.length; j++) {
            assertEq(hits[j], 1, configs[j].underlying);
        }
    }

    function testEveryTokenRowIsExactlyOneDeclaredTokenSuite() external view {
        assertOneSuitePerRow(declaredSuitesWhere(declaration(), isTokenSuite));
    }

    function testEveryTokenRowIsExactlyOneDeclaredWrapperSuite() external view {
        assertOneSuitePerRow(declaredSuitesWhere(declaration(), isWrapperSuite));
    }

    /// The key is held to the symbol case-insensitively; its alphabet is the framework's key check.
    function testEachTokenSuiteIsKeyedByAndDeploysItsUnderlyingsToken() external view {
        DeploySuite[] memory suites = declaredSuitesWhere(declaration(), isTokenSuite);
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        RegistryBeaconProxyParams[] memory params = LibProdTokenParams.tokenParams(configs);
        for (uint256 i = 0; i < suites.length; i++) {
            uint256 j = configIndexOf(configs, suites[i]);
            RegistryBeaconProxyParams memory suiteParams =
                LibRainDeployCloneMechanism.registryBeaconProxyParams(suites[i]);
            assertEq(
                vm.toLowercase(suites[i].suite),
                vm.toLowercase(string.concat(TOKEN_PREFIX, configs[j].symbol)),
                configs[j].underlying
            );
            assertEq(abi.encode(suiteParams), abi.encode(params[j]), configs[j].underlying);
            (, StoxTokenConfigV1 memory config) = abi.decode(suiteParams.data, (bytes32, StoxTokenConfigV1));
            assertEq(config.assetId, configs[j].assetId, configs[j].underlying);
            assertEq(config.listingTicker, configs[j].listingTicker, configs[j].underlying);
            assertEq(config.listingName, configs[j].listingName, configs[j].underlying);
        }
    }

    function testEachWrapperSuiteIsKeyedByAndWrapsItsUnderlyingsToken() external view {
        DeployDeclaration memory declared = declaration();
        DeploySuite[] memory all = allSuites(declared);
        DeploySuite[] memory wrappers = declaredSuitesWhere(declared, isWrapperSuite);
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        for (uint256 i = 0; i < wrappers.length; i++) {
            TokenConfig memory config = configs[configIndexOf(configs, wrappers[i])];
            DeploySuite memory token = suiteNamed(all, tokenKey(config));
            assertEq(
                vm.toLowercase(wrappers[i].suite),
                vm.toLowercase(string.concat(TOKEN_PREFIX, config.symbol, WRAPPER_SUFFIX)),
                config.underlying
            );
            RegistryBeaconProxyParams memory params = LibRainDeployCloneMechanism.registryBeaconProxyParams(wrappers[i]);
            assertEq(params.factory, CLONE_FACTORY_V8_ADDRESS, config.underlying);
            assertEq(params.registry, CONFIG_REGISTRY_ADDRESS, config.underlying);
            assertEq(params.authority, LibRegistryAuthority.ROOT_AUTHORITY, config.underlying);
            assertEq(params.data, abi.encode(token.storedDeployedAddress), config.underlying);
            assertTrue(wrappers[i].storedDeployedAddress != token.storedDeployedAddress, config.underlying);
        }
    }

    function testEachTokenSuiteProxiesAndDependsOnTheReceiptVaultBeaconSuite() external view {
        DeployDeclaration memory declared = declaration();
        (DeploySuite memory beacon, bool found) = candidateOf(declared, RECEIPT_VAULT_BEACON);
        assertTrue(found, RECEIPT_VAULT_BEACON);
        DeploySuite[] memory suites = declaredSuitesWhere(declared, isTokenSuite);
        for (uint256 i = 0; i < suites.length; i++) {
            assertEq(
                LibRainDeployCloneMechanism.registryBeaconProxyParams(suites[i]).beacon,
                beacon.storedDeployedAddress,
                suites[i].suite
            );
            assertEq(
                dependencyCodeHash(suites[i], beacon.storedDeployedAddress), beacon.storedBytecodeHash, suites[i].suite
            );
        }
    }

    function testEachWrapperSuiteProxiesAndDependsOnTheWrappedTokenVaultBeaconSuiteAndItsToken() external view {
        DeployDeclaration memory declared = declaration();
        (DeploySuite memory beacon, bool found) = candidateOf(declared, WRAPPED_TOKEN_VAULT_BEACON);
        assertTrue(found, WRAPPED_TOKEN_VAULT_BEACON);
        DeploySuite[] memory all = allSuites(declared);
        DeploySuite[] memory wrappers = declaredSuitesWhere(declared, isWrapperSuite);
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        for (uint256 i = 0; i < wrappers.length; i++) {
            DeploySuite memory token = suiteNamed(all, tokenKey(configs[configIndexOf(configs, wrappers[i])]));
            assertEq(
                LibRainDeployCloneMechanism.registryBeaconProxyParams(wrappers[i]).beacon,
                beacon.storedDeployedAddress,
                wrappers[i].suite
            );
            assertEq(
                dependencyCodeHash(wrappers[i], beacon.storedDeployedAddress),
                beacon.storedBytecodeHash,
                wrappers[i].suite
            );
            assertEq(
                dependencyCodeHash(wrappers[i], token.storedDeployedAddress),
                token.storedBytecodeHash,
                wrappers[i].suite
            );
        }
    }

    function deploySuite(
        DeployDeclaration memory declared,
        DeploySuite[] memory all,
        string memory key,
        SupportedNetwork memory network
    ) internal returns (address) {
        DeploySuite memory suite = suiteNamed(all, key);
        address deployed =
            deployStep(declared, suite)(vm, network.name, DEPLOYER, deployStepData(declared, suite, network.chainId));
        string memory label = string.concat(key, " on ", network.name);
        assertEq(deployed, suite.storedDeployedAddress, label);
        assertEq(deployed.code, suite.storedRuntimeCode, label);
        assertEq(deployed.codehash, suite.storedBytecodeHash, label);
        return deployed;
    }

    function assertToken(
        StoxReceiptVault token,
        TokenConfig memory config,
        IAuthorizeV1 authorizer,
        string memory label
    ) internal view {
        bool us = config.region == Region.US;
        assertEq(token.name(), string.concat(config.listingName, ST0X_NAME_SUFFIX), label);
        assertEq(token.symbol(), string.concat("t", config.listingTicker), label);
        assertEq(token.owner(), us ? US_OWNER : EU_OWNER, label);
        assertEq(address(token.authorizer()), address(authorizer), label);
        assertEq(
            address(token.receipt()),
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

    function testEveryTokenAndWrapperSuiteLandsAtItsStoredAddressOnEveryNetwork() external {
        (IAuthorizeV1 usAuthorizer, IAuthorizeV1 euAuthorizer) =
            LibTestTokenEnvironment.deploy(vm, TIMELOCK, US_OWNER, EU_OWNER);
        address wrapperBeacon = LibRainDeploy.deployZoltu(V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CREATION_CODE_CANDIDATE);
        LibTestDeploy.bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.WRAPPER_BEACON_NAME,
            "address",
            abi.encode(wrapperBeacon)
        );
        DeployDeclaration memory declared = declaration();
        DeploySuite[] memory all = allSuites(declared);
        SupportedNetwork[] memory networks = LibRainDeploy.declaredNetworkConfigs(declared.deployNetworks);
        assertTrue(networks.length > 0, "networks");
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 preDeploy = vm.snapshotState();
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < configs.length; j++) {
                string memory key = tokenKey(configs[j]);
                string memory label = string.concat(key, " on ", networks[i].name);
                address token = deploySuite(declared, all, key, networks[i]);
                assertToken(
                    StoxReceiptVault(payable(token)),
                    configs[j],
                    configs[j].region == Region.US ? usAuthorizer : euAuthorizer,
                    label
                );
                address wrapper = deploySuite(declared, all, string.concat(key, WRAPPER_SUFFIX), networks[i]);
                assertEq(StoxWrappedTokenVault(wrapper).asset(), token, label);
            }
            assertTrue(vm.revertToState(preDeploy), networks[i].name);
        }
    }
}
