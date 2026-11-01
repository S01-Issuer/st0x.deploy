// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.29/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, DeployDependency, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    CREATION_CODE as CONFIG_REGISTRY_CREATION_CODE
} from "rain-deploy-0.1.29/src/generated/0_1_29/ConfigRegistry.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V7_ADDRESS,
    CREATION_CODE as CLONE_FACTORY_V7_CREATION_CODE
} from "rain-factory-deploy-0.2.4/src/generated/0_2_4/CloneFactory.sol";
import {CloneFactory} from "rain-factory-deploy-0.2.4/src/concrete/CloneFactory.sol";
import {ICloneableFactoryV7} from "rain-factory-0.2.7/src/interface/ICloneableFactoryV7.sol";
import {RegistryBeaconProxyTarget} from "rain-factory-0.2.7/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {REGISTRY_BEACON_PROXY_MECHANISM} from "rain-factory-0.2.7/src/lib/LibRainDeployCloneMechanism.sol";
import {IAuthorizeV1} from "rain-vats-0.2.13/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE
} from "rain-vats-0.2.13/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {
    OffchainAssetReceiptVaultConfigV3,
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG
} from "rain-vats-0.2.13/src/interface/IOffchainAssetReceiptVaultV1.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.13/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibProdDeployV4 as V4} from "../../../src/generated/LibProdDeployV4.sol";
import {IST0xVaultBeaconSet} from "../../../src/interface/IST0xVaultBeaconSet.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

/// @title StoxDeployTokenSuitesTest
/// @notice Every production token is declared as a registry beacon proxy of
/// the V7 clone factory over the root's vault beacon binding, and the
/// declaration matches what that factory deploys locally.
contract StoxDeployTokenSuitesTest is Test, StoxDeploySuites {
    address internal constant US_OWNER = address(uint160(uint256(keccak256("st0x.test.token-suites.us-owner"))));
    address internal constant EU_OWNER = address(uint160(uint256(keccak256("st0x.test.token-suites.eu-owner"))));

    function tokenSuite(DeployDeclaration memory declared, TokenConfig memory config)
        internal
        pure
        returns (DeploySuite memory, RegistryBeaconProxyTarget memory)
    {
        (DeploySuite memory suite, bool found) = candidateOf(declared, string.concat("stox-token-", config.underlying));
        assertTrue(found, config.underlying);
        (bytes32 mechanism, bytes memory targetData) = abi.decode(suite.mechanismData, (bytes32, bytes));
        assertEq(mechanism, REGISTRY_BEACON_PROXY_MECHANISM, config.underlying);
        return (suite, abi.decode(targetData, (RegistryBeaconProxyTarget)));
    }

    /// The frozen 0.1.1 beacon-set deployer at its Zoltu address, over the
    /// frozen implementations its constructor builds beacons for.
    function deployVaultBeaconSet() internal returns (IST0xVaultBeaconSet) {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(V4.STOX_RECEIPT_CREATION_CODE_0_1_1);
        LibRainDeploy.deployZoltu(V4.STOX_RECEIPT_VAULT_CREATION_CODE_0_1_1);
        address deployer =
            LibRainDeploy.deployZoltu(V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_1);
        assertEq(deployer, V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1, "beacon set deployer");
        return IST0xVaultBeaconSet(deployer);
    }

    /// The V7 clone factory and V5 ConfigRegistry from their creation code,
    /// at their Zoltu addresses.
    function deployFactoryAndRegistry() internal {
        assertEq(LibRainDeploy.deployZoltu(CLONE_FACTORY_V7_CREATION_CODE), CLONE_FACTORY_V7_ADDRESS, "factory");
        assertEq(LibRainDeploy.deployZoltu(CONFIG_REGISTRY_CREATION_CODE), CONFIG_REGISTRY_ADDRESS, "registry");
    }

    function upgrade(address beacon, address implementation) internal {
        vm.prank(UpgradeableBeacon(beacon).owner());
        UpgradeableBeacon(beacon).upgradeTo(implementation);
    }

    function newAuthorizer(address admin) internal returns (IAuthorizeV1) {
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        return IAuthorizeV1(
            new CloneFactory()
                .cloneDeterministic(
                    address(impl),
                    abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: admin})),
                    bytes32(uint256(uint160(admin)))
                )
        );
    }

    function bindRbac(bytes32 name, address owner, IAuthorizeV1 authorizer) internal {
        LibTestDeploy.bind(
            vm,
            LibStoxConfig.ROOT_AUTHORITY,
            name,
            OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE,
            abi.encode(OffchainAssetReceiptVaultRbacV1({owner: owner, authorizer: authorizer}))
        );
    }

    function testVaultBeaconIsTheBeaconSetDeployersVaultBeacon() external {
        IST0xVaultBeaconSet set = deployVaultBeaconSet();
        assertEq(address(set.iOffchainAssetReceiptVaultBeacon()), vaultBeacon());
    }

    function testEveryProductionTokenIsOneRegistryBeaconProxySuite() external view {
        DeployDeclaration memory declared = declaration();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        uint256 registryBeaconProxies = 0;
        for (uint256 i = 0; i < declared.candidates.length; i++) {
            bytes32 mechanism = mechanismIdOf(declared.candidates[i].snapshot);
            if (mechanism == REGISTRY_BEACON_PROXY_MECHANISM) {
                registryBeaconProxies++;
            }
        }
        assertEq(registryBeaconProxies, configs.length, "registry beacon proxy suites");
        for (uint256 i = 0; i < configs.length; i++) {
            tokenSuite(declared, configs[i]);
        }
    }

    function testTokenSuitesTargetTheV7FactoryOverTheRootVaultBeaconBinding() external {
        address beacon = address(deployVaultBeaconSet().iOffchainAssetReceiptVaultBeacon());
        DeployDeclaration memory declared = declaration();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 i = 0; i < configs.length; i++) {
            (, RegistryBeaconProxyTarget memory target) = tokenSuite(declared, configs[i]);
            assertEq(target.factory, CLONE_FACTORY_V7_ADDRESS, "factory");
            assertEq(target.registry, CONFIG_REGISTRY_ADDRESS, "registry");
            assertEq(target.authority, LibStoxConfig.ROOT_AUTHORITY, "authority");
            assertEq(target.beaconName, LibStoxConfig.VAULT_BEACON_NAME, "beacon name");
            assertEq(target.beacon, beacon, "beacon");
            assertEq(target.salt, keccak256(bytes(configs[i].underlying)), "salt");
        }
    }

    function testTokenSuiteDataIsTheCanonicalV3ConfigOfItsTableRow() external view {
        DeployDeclaration memory declared = declaration();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 i = 0; i < configs.length; i++) {
            (, RegistryBeaconProxyTarget memory target) = tokenSuite(declared, configs[i]);
            (bytes32 tag, OffchainAssetReceiptVaultConfigV3 memory config) =
                abi.decode(target.data, (bytes32, OffchainAssetReceiptVaultConfigV3));
            assertEq(keccak256(abi.encode(tag, config)), keccak256(target.data), "canonical");
            assertEq(tag, OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG, "tag");
            assertEq(config.name, configs[i].name, "name");
            assertEq(config.symbol, configs[i].symbol, "symbol");
            assertEq(config.authority, LibStoxConfig.ROOT_AUTHORITY, "authority");
            assertEq(
                config.rbacName,
                configs[i].region == Region.US ? LibStoxConfig.RBAC_US_NAME : LibStoxConfig.RBAC_EU_NAME,
                "rbac name"
            );
            assertEq(config.receiptBeaconName, LibStoxConfig.RECEIPT_BEACON_NAME, "receipt beacon name");
            assertEq(config.metadata, "", "metadata");
        }
    }

    function testTokenSuitesAreTheSameOnEveryDeploymentNetwork() external {
        DeployDeclaration memory baseline = declaration();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 n = 0; n < networks.length; n++) {
            vm.chainId(networks[n].chainId);
            DeployDeclaration memory declared = declaration();
            for (uint256 i = 0; i < configs.length; i++) {
                (DeploySuite memory expected,) = tokenSuite(baseline, configs[i]);
                (DeploySuite memory suite,) = tokenSuite(declared, configs[i]);
                assertEq(suite.mechanismData, expected.mechanismData, networks[n].name);
                assertEq(suite.storedRuntimeCode, expected.storedRuntimeCode, networks[n].name);
                assertEq(
                    deployedAddress(declared, suite, networks[n].chainId),
                    expected.storedDeployedAddress,
                    networks[n].name
                );
            }
        }
    }

    function testTokenSuiteDependenciesAreTheFactoryRegistryAndVaultBeaconAsDeployed() external {
        address beacon = address(deployVaultBeaconSet().iOffchainAssetReceiptVaultBeacon());
        deployFactoryAndRegistry();
        DeployDeclaration memory declared = declaration();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 i = 0; i < configs.length; i++) {
            (DeploySuite memory suite,) = tokenSuite(declared, configs[i]);
            DeployDependency[] memory deps = suite.dependencies;
            assertEq(deps.length, 3, "dependencies");
            assertEq(deps[0].deployedAddress, CLONE_FACTORY_V7_ADDRESS, "factory address");
            assertEq(deps[0].runtimeCode, CLONE_FACTORY_V7_ADDRESS.code, "factory code");
            assertEq(deps[1].deployedAddress, CONFIG_REGISTRY_ADDRESS, "registry address");
            assertEq(deps[1].runtimeCode, CONFIG_REGISTRY_ADDRESS.code, "registry code");
            assertEq(deps[2].deployedAddress, beacon, "beacon address");
            assertEq(deps[2].runtimeCode, beacon.code, "beacon code");
        }
    }

    function testEachTokenSuiteIsWhatTheV7FactoryDeploysFromIt() external {
        IST0xVaultBeaconSet set = deployVaultBeaconSet();
        LibTestDeploy.deployImplementations(vm);
        LibRainDeploy.deployZoltu(type(StoxCorporateActionsFacet).creationCode);
        upgrade(address(set.iReceiptBeacon()), V4.STOX_RECEIPT_CANDIDATE);
        upgrade(address(set.iOffchainAssetReceiptVaultBeacon()), V4.STOX_RECEIPT_VAULT_CANDIDATE);
        deployFactoryAndRegistry();
        IAuthorizeV1 usAuthorizer = newAuthorizer(US_OWNER);
        IAuthorizeV1 euAuthorizer = newAuthorizer(EU_OWNER);
        LibTestDeploy.bind(
            vm,
            LibStoxConfig.ROOT_AUTHORITY,
            LibStoxConfig.VAULT_BEACON_NAME,
            "address",
            abi.encode(address(set.iOffchainAssetReceiptVaultBeacon()))
        );
        LibTestDeploy.bind(
            vm,
            LibStoxConfig.ROOT_AUTHORITY,
            LibStoxConfig.RECEIPT_BEACON_NAME,
            "address",
            abi.encode(address(set.iReceiptBeacon()))
        );
        bindRbac(LibStoxConfig.RBAC_US_NAME, US_OWNER, usAuthorizer);
        bindRbac(LibStoxConfig.RBAC_EU_NAME, EU_OWNER, euAuthorizer);

        DeployDeclaration memory declared = declaration();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        ICloneableFactoryV7 factory = ICloneableFactoryV7(CLONE_FACTORY_V7_ADDRESS);
        for (uint256 i = 0; i < configs.length; i++) {
            (DeploySuite memory suite, RegistryBeaconProxyTarget memory target) = tokenSuite(declared, configs[i]);
            assertEq(
                factory.predictRegistryBeaconProxyAddress(
                    target.registry, target.authority, target.beaconName, target.data, target.salt
                ),
                suite.storedDeployedAddress,
                "predicted"
            );
            address deployed = factory.registryBeaconProxy(
                target.registry, target.authority, target.beaconName, target.data, target.salt
            );
            assertEq(deployed, suite.storedDeployedAddress, "address");
            assertEq(deployed.code, suite.storedRuntimeCode, "runtime code");
            assertEq(deployed.codehash, suite.storedBytecodeHash, "code hash");

            StoxReceiptVault token = StoxReceiptVault(payable(deployed));
            bool us = configs[i].region == Region.US;
            assertEq(token.name(), configs[i].name, "name");
            assertEq(token.symbol(), configs[i].symbol, "symbol");
            assertEq(token.owner(), us ? US_OWNER : EU_OWNER, "owner");
            assertEq(address(token.authorizer()), address(us ? usAuthorizer : euAuthorizer), "authorizer");
        }
    }
}
