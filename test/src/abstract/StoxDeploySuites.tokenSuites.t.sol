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
import {Region, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenTargets} from "../../../src/lib/LibProdTokenTargets.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibTestTokenConfigs} from "../../lib/LibTestTokenConfigs.sol";
import {IStoxAssetIdV1} from "../../../src/interface/IStoxAssetIdV1.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {StoxGovernanceTimelock} from "../../../src/concrete/StoxGovernanceTimelock.sol";
import {LibProdDeployCurrent} from "../../../src/generated/LibProdDeployCurrent.sol";
import {IStoxUnderlyingV1} from "../../../src/interface/IStoxUnderlyingV1.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {ST0X_NAME_SUFFIX} from "../../../src/lib/LibUnderlying.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LibStoxTestTokens} from "../../../src/lib/LibStoxTestTokens.sol";
import {LibTestTokenEnvironment} from "../../lib/LibTestTokenEnvironment.sol";

/// @title StoxDeploySuitesTokenSuitesTest
/// @notice Every V6 token row (the production rows with an asset id, then the test tokens) is exactly one declared
/// registry beacon proxy suite over the vault beacon, keyed by its symbol, deploying the nameless target its asset id
/// salts, and landing at its stored address with its stored runtime code.
contract StoxDeploySuitesTokenSuitesTest is Test, StoxDeploySuites {
    address internal constant US_OWNER = address(uint160(uint256(keccak256("st0x.test.token-suites.us-owner"))));
    address internal constant EU_OWNER = address(uint160(uint256(keccak256("st0x.test.token-suites.eu-owner"))));
    address internal constant DEPLOYER = address(uint160(uint256(keccak256("st0x.test.token-suites.deployer"))));
    address internal constant TIMELOCK = address(uint160(uint256(keccak256("st0x.test.token-suites.timelock"))));
    address internal constant SAFE = address(uint160(uint256(keccak256("st0x.test.token-suites.safe"))));

    function isTokenSuite(DeploySuite memory suite) internal pure returns (bool) {
        return mechanismIdOf(suite) == REGISTRY_BEACON_PROXY_MECHANISM
            && LibRainDeployCloneMechanism.registryBeaconProxyTarget(suite).beaconName
                == LibStoxConfig.VAULT_BEACON_NAME;
    }

    /// Released and candidate suites alike, so a token declared as a release is counted.
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

    /// @return The index of the one config whose asset id salts `suite`'s target and whose region's RBAC its data
    /// names. The salt alone is not enough: a US and an EU row can share an asset id.
    function configIndexOf(TokenConfig[] memory configs, DeploySuite memory suite) internal pure returns (uint256) {
        RegistryBeaconProxyTarget memory target = LibRainDeployCloneMechanism.registryBeaconProxyTarget(suite);
        (, OffchainAssetReceiptVaultConfigV3 memory config) =
            abi.decode(target.data, (bytes32, OffchainAssetReceiptVaultConfigV3));
        uint256 matches = 0;
        uint256 index = 0;
        for (uint256 j = 0; j < configs.length; j++) {
            bytes32 rbacName = configs[j].region == Region.US ? LibStoxConfig.RBAC_US_NAME : LibStoxConfig.RBAC_EU_NAME;
            if (keccak256(bytes(configs[j].assetId)) == target.salt && rbacName == config.rbacName) {
                matches++;
                index = j;
            }
        }
        assertEq(matches, 1, suite.suite);
        return index;
    }

    function testEveryV6TokenIsExactlyOneDeclaredSuite() external view {
        DeploySuite[] memory suites = declaredTokenSuites(declaration());
        TokenConfig[] memory configs = LibTestTokenConfigs.v6AndTestTokenConfigs();
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
        TokenConfig[] memory configs = LibTestTokenConfigs.v6AndTestTokenConfigs();
        for (uint256 i = 0; i < suites.length; i++) {
            uint256 j = configIndexOf(configs, suites[i]);
            RegistryBeaconProxyTarget memory target = LibRainDeployCloneMechanism.registryBeaconProxyTarget(suites[i]);
            assertEq(
                vm.toLowercase(suites[i].suite),
                vm.toLowercase(string.concat(TOKEN_PREFIX, configs[j].symbol)),
                configs[j].underlying
            );
            assertEq(abi.encode(target), abi.encode(LibProdTokenTargets.tokenTarget(configs[j])), configs[j].underlying);
            (, OffchainAssetReceiptVaultConfigV3 memory config) =
                abi.decode(target.data, (bytes32, OffchainAssetReceiptVaultConfigV3));
            assertEq(config.symbol, "", configs[j].underlying);
            assertEq(config.name, "", configs[j].underlying);
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
        TokenConfig[] memory configs = LibTestTokenConfigs.v6AndTestTokenConfigs();
        assertEq(suites.length, configs.length, "suites");
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
            assertEq(token.symbol(), "", suite.suite);
            assertEq(token.name(), "", suite.suite);
            assertEq(IStoxAssetIdV1(deployed).assetId(), config.assetId, suite.suite);
            assertEq(token.owner(), us ? US_OWNER : EU_OWNER, suite.suite);
            assertEq(address(token.authorizer()), address(us ? usAuthorizer : euAuthorizer), suite.suite);
        }
    }

    /// A test token deploys nameless through its suite with the real governance timelock as its owner; the first
    /// `setUnderlying` is a timelock operation that executes after the 48h delay and names the token, keeping its
    /// address and asset id.
    function testNamelessTokenIsNamedThroughTheTimelock() external {
        address timelockAddress = LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK;
        LibTestTokenEnvironment.deploy(vm, TIMELOCK, timelockAddress, timelockAddress);
        LibTestDeploy.bind(
            vm, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.TIMELOCK_INITIAL_PROPOSER_NAME, "address", abi.encode(SAFE)
        );
        TimelockController timelock =
            TimelockController(payable(LibRainDeploy.deployZoltu(type(StoxGovernanceTimelock).creationCode)));
        assertEq(address(timelock), timelockAddress, "timelock address");

        TokenConfig memory config = LibStoxTestTokens.testTokenConfigs()[0];
        DeployDeclaration memory declared = declaration();
        DeploySuite memory suite = suiteByName(declared, string.concat(TOKEN_PREFIX, lowercase(config.symbol)));
        address deployed =
            deployStep(declared, suite)(vm, "base", DEPLOYER, deployStepData(declared, suite, block.chainid));
        assertEq(deployed, suite.storedDeployedAddress, "address");
        StoxReceiptVault token = StoxReceiptVault(payable(deployed));
        assertEq(token.owner(), timelockAddress, "owner");
        assertEq(IStoxAssetIdV1(deployed).assetId(), config.assetId, "asset id");
        assertEq(token.name(), "", "nameless");
        assertEq(token.symbol(), "", "symbolless");

        bytes memory payload =
            abi.encodeCall(IStoxUnderlyingV1.setUnderlying, (config.underlying, config.underlyingName));
        bytes32 salt = keccak256("st0x.test.first-set-underlying");
        vm.prank(SAFE);
        timelock.schedule(deployed, 0, payload, bytes32(0), salt, LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                timelock.hashOperation(deployed, 0, payload, bytes32(0), salt),
                bytes32(uint256(2) ** uint8(TimelockController.OperationState.Ready))
            )
        );
        timelock.execute(deployed, 0, payload, bytes32(0), salt);

        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        timelock.execute(deployed, 0, payload, bytes32(0), salt);

        assertEq(token.symbol(), string.concat("t", config.underlying), "symbol");
        assertEq(token.name(), string.concat(config.underlyingName, ST0X_NAME_SUFFIX), "name");
        assertEq(token.symbol(), config.symbol, "symbol is the table symbol");
        assertEq(IStoxAssetIdV1(deployed).assetId(), config.assetId, "asset id kept");
        assertEq(deployed, suite.storedDeployedAddress, "address kept");
    }

    /// Two rows that share an asset id, one per region, each match their own suite.
    function testSaltAndRegionMatchEachRegionalRowSharingAnAssetId() external pure {
        TokenConfig[] memory configs = LibStoxTestTokens.testTokenConfigs();
        configs[1].assetId = configs[0].assetId;
        RegistryBeaconProxyTarget[] memory targets = LibProdTokenTargets.tokenTargets(configs);
        for (uint256 i = 0; i < configs.length; i++) {
            DeploySuite memory suite;
            suite.suite = configs[i].symbol;
            suite.mechanismData = abi.encode(REGISTRY_BEACON_PROXY_MECHANISM, abi.encode(targets[i]));
            suite.dependencies = LibProdTokenTargets.tokenDependencies();
            assertEq(configIndexOf(configs, suite), i, configs[i].underlying);
        }
    }
}
