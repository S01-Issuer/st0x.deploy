// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {DeployDependency, LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    CREATION_CODE as CONFIG_REGISTRY_CREATION_CODE
} from "rain-deploy-0.1.29/src/generated/0_1_29/ConfigRegistry.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V8_ADDRESS,
    CREATION_CODE as CLONE_FACTORY_V8_CREATION_CODE
} from "rain-factory-deploy-0.2.5/src/generated/0_2_5/CloneFactory.sol";
import {CloneFactory} from "rain-factory-deploy-0.2.5/src/concrete/CloneFactory.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyTarget
} from "rain-factory-0.2.9/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {IAuthorizeV1} from "rain-vats-0.2.16/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE
} from "rain-vats-0.2.16/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {
    OffchainAssetReceiptVaultConfigV3,
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG
} from "rain-vats-0.2.16/src/interface/IOffchainAssetReceiptVaultV1.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.16/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibProdDeployV4 as V4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibStoxTokenProxy} from "../../../src/generated/LibStoxTokenProxy.sol";
import {IST0xVaultBeaconSet} from "../../../src/interface/IST0xVaultBeaconSet.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenTargets} from "../../../src/lib/LibProdTokenTargets.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

/// @title LibProdTokenTargetsTest
/// @notice One V8 registry beacon proxy per production token row; each row's deploy step lands its token.
    address internal constant US_OWNER = address(uint160(uint256(keccak256("st0x.test.token-targets.us-owner"))));
    address internal constant EU_OWNER = address(uint160(uint256(keccak256("st0x.test.token-targets.eu-owner"))));
    address internal constant DEPLOYER = address(uint160(uint256(keccak256("st0x.test.token-targets.deployer"))));

    /// The frozen 0.1.1 beacon-set deployer at its Zoltu address.
    function deployVaultBeaconSet() internal returns (IST0xVaultBeaconSet) {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(V4.STOX_RECEIPT_CREATION_CODE_0_1_1);
        LibRainDeploy.deployZoltu(V4.STOX_RECEIPT_VAULT_CREATION_CODE_0_1_1);
        address deployer =
            LibRainDeploy.deployZoltu(V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_1);
        assertEq(deployer, V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1, "beacon set deployer");
        return IST0xVaultBeaconSet(deployer);
    }

    function deployFactoryAndRegistry() internal {
        assertEq(LibRainDeploy.deployZoltu(CLONE_FACTORY_V8_CREATION_CODE), CLONE_FACTORY_V8_ADDRESS, "factory");
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
        assertEq(address(deployVaultBeaconSet().iOffchainAssetReceiptVaultBeacon()), LibProdTokenTargets.vaultBeacon());
    }

    function testEachTargetIsARegistryBeaconProxyOfItsRowOverTheRootVaultBeacon() external pure {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        RegistryBeaconProxyTarget[] memory targets = LibProdTokenTargets.tokenTargets();
        assertEq(targets.length, configs.length, "one target per row");
        for (uint256 i = 0; i < targets.length; i++) {
            assertEq(targets[i].factory, CLONE_FACTORY_V8_ADDRESS, configs[i].underlying);
            assertEq(targets[i].registry, CONFIG_REGISTRY_ADDRESS, configs[i].underlying);
            assertEq(targets[i].authority, LibStoxConfig.ROOT_AUTHORITY, configs[i].underlying);
            assertEq(targets[i].beaconName, LibStoxConfig.VAULT_BEACON_NAME, configs[i].underlying);
            assertEq(targets[i].beacon, LibProdTokenTargets.vaultBeacon(), configs[i].underlying);
            assertEq(targets[i].salt, keccak256(bytes(configs[i].underlying)), configs[i].underlying);
        }
    }

    function testEachTargetDataIsTheCanonicalV3ConfigOfItsRow() external pure {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        RegistryBeaconProxyTarget[] memory targets = LibProdTokenTargets.tokenTargets();
        for (uint256 i = 0; i < targets.length; i++) {
            (bytes32 tag, OffchainAssetReceiptVaultConfigV3 memory config) =
                abi.decode(targets[i].data, (bytes32, OffchainAssetReceiptVaultConfigV3));
            assertEq(abi.encode(tag, config), targets[i].data, "canonical");
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

    function testEveryRowLandsAtItsOwnAddress() external pure {
        RegistryBeaconProxyTarget[] memory targets = LibProdTokenTargets.tokenTargets();
        for (uint256 i = 0; i < targets.length; i++) {
            address proxy = LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(targets[i]);
            for (uint256 j = 0; j < i; j++) {
                assertNotEq(LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(targets[j]), proxy);
            }
        }
    }

    function testTargetsAreTheSameOnEveryDeploymentNetwork() external {
        bytes memory baseline = abi.encode(LibProdTokenTargets.tokenTargets());
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 n = 0; n < networks.length; n++) {
            vm.chainId(networks[n].chainId);
            assertEq(abi.encode(LibProdTokenTargets.tokenTargets()), baseline, networks[n].name);
        }
    }

    function testDependenciesAreTheV8FactoryRegistryAndVaultBeaconAsDeployed() external {
        address beacon = address(deployVaultBeaconSet().iOffchainAssetReceiptVaultBeacon());
        deployFactoryAndRegistry();
        DeployDependency[] memory deps = LibProdTokenTargets.tokenDependencies();
        assertEq(deps.length, 3, "dependencies");
        assertEq(deps[0].deployedAddress, CLONE_FACTORY_V8_ADDRESS, "factory address");
        assertEq(deps[0].runtimeCode, CLONE_FACTORY_V8_ADDRESS.code, "factory code");
        assertEq(deps[1].deployedAddress, CONFIG_REGISTRY_ADDRESS, "registry address");
        assertEq(deps[1].runtimeCode, CONFIG_REGISTRY_ADDRESS.code, "registry code");
        assertEq(deps[2].deployedAddress, beacon, "beacon address");
        assertEq(deps[2].runtimeCode, beacon.code, "beacon code");
    }

    function testEachRowsDeployStepLandsItsTokenAtItsAddress() external {
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

        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        RegistryBeaconProxyTarget[] memory targets = LibProdTokenTargets.tokenTargets();
        for (uint256 i = 0; i < targets.length; i++) {
            address deployed = LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployStep(
                vm, "base", DEPLOYER, abi.encode(targets[i])
            );
            assertEq(
                deployed, LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(targets[i]), "address"
            );
            assertEq(deployed.code, LibStoxTokenProxy.RUNTIME_CODE, "runtime code");

            StoxReceiptVault token = StoxReceiptVault(payable(deployed));
            bool us = configs[i].region == Region.US;
            assertEq(token.name(), configs[i].name, "name");
            assertEq(token.symbol(), configs[i].symbol, "symbol");
            assertEq(token.owner(), us ? US_OWNER : EU_OWNER, "owner");
            assertEq(address(token.authorizer()), address(us ? usAuthorizer : euAuthorizer), "authorizer");
        }
    }
}
