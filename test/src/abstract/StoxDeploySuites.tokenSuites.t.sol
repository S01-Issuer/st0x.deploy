// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {
    LibRainDeployCloneMechanism,
    REGISTRY_BEACON_PROXY_MECHANISM
} from "rain-factory-0.2.10/src/lib/LibRainDeployCloneMechanism.sol";
import {RegistryBeaconProxyTarget} from "rain-factory-0.2.10/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {IAuthorizeV1} from "rain-vats-0.2.18/src/interface/IAuthorizeV1.sol";
import {OffchainAssetReceiptVaultConfigV3} from "rain-vats-0.2.18/src/interface/IOffchainAssetReceiptVaultV1.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenTargets} from "../../../src/lib/LibProdTokenTargets.sol";
import {LibTestTokenEnvironment} from "../../lib/LibTestTokenEnvironment.sol";

/// @title StoxDeploySuitesTokenSuitesTest
/// @notice Every production token is exactly one declared registry beacon proxy suite, keyed by its symbol, deploying
/// the target its underlying salts, and landing at its stored address with its stored runtime code.
contract StoxDeploySuitesTokenSuitesTest is Test, StoxDeploySuites {
    address internal constant US_OWNER = address(uint160(uint256(keccak256("st0x.test.token-suites.us-owner"))));
    address internal constant EU_OWNER = address(uint160(uint256(keccak256("st0x.test.token-suites.eu-owner"))));
    address internal constant DEPLOYER = address(uint160(uint256(keccak256("st0x.test.token-suites.deployer"))));
    address internal constant TIMELOCK = address(uint160(uint256(keccak256("st0x.test.token-suites.timelock"))));

    /// Every registry beacon proxy suite but the orchestrator instance, released and candidate alike, so a token
    /// declared as a release is counted.
    function declaredTokenSuites(DeployDeclaration memory declared) internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory found = new DeploySuite[](declared.released.length + declared.candidates.length);
        uint256 count = 0;
        for (uint256 i = 0; i < declared.released.length; i++) {
            if (isTokenSuite(declared.released[i])) {
                found[count++] = declared.released[i];
            }
        }
        for (uint256 i = 0; i < declared.candidates.length; i++) {
            if (isTokenSuite(declared.candidates[i].snapshot)) {
                found[count++] = declared.candidates[i].snapshot;
            }
        }
        assembly ("memory-safe") {
            mstore(found, count)
        }
        return found;
    }

    function isTokenSuite(DeploySuite memory suite) internal pure returns (bool) {
        return mechanismIdOf(suite) == REGISTRY_BEACON_PROXY_MECHANISM
            && keccak256(bytes(suite.suite)) != keccak256(bytes(ORCHESTRATOR_PROXY));
    }

    /// @return The index of the one config whose underlying salts `suite`'s target.
    function configIndexOf(TokenConfig[] memory configs, DeploySuite memory suite) internal pure returns (uint256) {
        bytes32 salt = LibRainDeployCloneMechanism.registryBeaconProxyTarget(suite).salt;
        uint256 matches = 0;
        uint256 index = 0;
        for (uint256 j = 0; j < configs.length; j++) {
            if (keccak256(bytes(configs[j].underlying)) == salt) {
                matches++;
                index = j;
            }
        }
        assertEq(matches, 1, suite.suite);
        return index;
    }

    function testEveryProductionTokenIsExactlyOneDeclaredSuite() external view {
        DeploySuite[] memory suites = declaredTokenSuites(declaration());
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        assertEq(suites.length, configs.length, "one suite per token");
        uint256[] memory hits = new uint256[](configs.length);
        for (uint256 i = 0; i < suites.length; i++) {
            hits[configIndexOf(configs, suites[i])]++;
        }
        for (uint256 j = 0; j < configs.length; j++) {
            assertEq(hits[j], 1, configs[j].underlying);
        }
    }

    /// The key is held to the symbol case-insensitively; its alphabet is the framework's key check.
    function testEachTokenSuiteIsKeyedByAndDeploysItsUnderlyingsToken() external view {
        DeploySuite[] memory suites = declaredTokenSuites(declaration());
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        RegistryBeaconProxyTarget[] memory targets = LibProdTokenTargets.tokenTargets();
        for (uint256 i = 0; i < suites.length; i++) {
            uint256 j = configIndexOf(configs, suites[i]);
            RegistryBeaconProxyTarget memory target = LibRainDeployCloneMechanism.registryBeaconProxyTarget(suites[i]);
            assertEq(
                vm.toLowercase(suites[i].suite),
                vm.toLowercase(string.concat(TOKEN_PREFIX, configs[j].symbol)),
                configs[j].underlying
            );
            assertEq(abi.encode(target), abi.encode(targets[j]), configs[j].underlying);
            (, OffchainAssetReceiptVaultConfigV3 memory config) =
                abi.decode(target.data, (bytes32, OffchainAssetReceiptVaultConfigV3));
            assertEq(config.symbol, configs[j].symbol, configs[j].underlying);
            assertEq(config.name, configs[j].name, configs[j].underlying);
        }
    }

    function testEachTokenSuiteProxiesAndDependsOnTheReceiptVaultBeaconSuite() external view {
        DeployDeclaration memory declared = declaration();
        (DeploySuite memory beacon, bool found) = candidateOf(declared, RECEIPT_VAULT_BEACON);
        assertTrue(found, RECEIPT_VAULT_BEACON);
        DeploySuite[] memory suites = declaredTokenSuites(declared);
        for (uint256 i = 0; i < suites.length; i++) {
            assertEq(
                LibRainDeployCloneMechanism.registryBeaconProxyTarget(suites[i]).beacon,
                beacon.storedDeployedAddress,
                suites[i].suite
            );
            uint256 matches = 0;
            for (uint256 j = 0; j < suites[i].dependencies.length; j++) {
                if (suites[i].dependencies[j].deployedAddress == beacon.storedDeployedAddress) {
                    matches++;
                    assertEq(
                        keccak256(suites[i].dependencies[j].runtimeCode), beacon.storedBytecodeHash, suites[i].suite
                    );
                }
            }
            assertEq(matches, 1, suites[i].suite);
        }
    }

    function testEachTokenSuiteDeploysAtItsStoredAddressWithItsStoredRuntimeCode() external {
        (IAuthorizeV1 usAuthorizer, IAuthorizeV1 euAuthorizer) =
            LibTestTokenEnvironment.deploy(vm, TIMELOCK, US_OWNER, EU_OWNER);
        DeployDeclaration memory declared = declaration();
        DeploySuite[] memory suites = declaredTokenSuites(declared);
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 i = 0; i < suites.length; i++) {
            DeploySuite memory suite = suites[i];
            address deployed =
                deployStep(declared, suite)(vm, "base", DEPLOYER, deployStepData(declared, suite, block.chainid));
            assertEq(deployed, suite.storedDeployedAddress, suite.suite);
            assertEq(deployed.code, suite.storedRuntimeCode, suite.suite);
            assertEq(deployed.codehash, suite.storedBytecodeHash, suite.suite);

            TokenConfig memory config = configs[configIndexOf(configs, suite)];
            StoxReceiptVault token = StoxReceiptVault(payable(deployed));
            bool us = config.region == Region.US;
            assertEq(token.symbol(), config.symbol, suite.suite);
            assertEq(token.owner(), us ? US_OWNER : EU_OWNER, suite.suite);
            assertEq(address(token.authorizer()), address(us ? usAuthorizer : euAuthorizer), suite.suite);
        }
    }
}
