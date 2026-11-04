// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {DeployDependency, LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V8_ADDRESS
} from "rain-factory-deploy-0.2.6/src/generated/0_2_5/CloneFactory.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyTarget
} from "rain-factory-0.2.10/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {IAuthorizeV1} from "rain-vats-0.2.18/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultConfigV3,
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG
} from "rain-vats-0.2.18/src/interface/IOffchainAssetReceiptVaultV1.sol";

import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {LibProdDeployCurrent} from "../../../src/generated/LibProdDeployCurrent.sol";
import {LibStoxTokenProxy} from "../../../src/generated/LibStoxTokenProxy.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenTargets} from "../../../src/lib/LibProdTokenTargets.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTestTokenEnvironment} from "../../lib/LibTestTokenEnvironment.sol";

/// @title LibProdTokenTargetsTest
/// @notice One V8 registry beacon proxy per production token row; each row's deploy step lands its token.
contract LibProdTokenTargetsTest is Test {
    address internal constant US_OWNER = address(uint160(uint256(keccak256("st0x.test.token-targets.us-owner"))));
    address internal constant EU_OWNER = address(uint160(uint256(keccak256("st0x.test.token-targets.eu-owner"))));
    address internal constant DEPLOYER = address(uint160(uint256(keccak256("st0x.test.token-targets.deployer"))));
    address internal constant TIMELOCK = address(uint160(uint256(keccak256("st0x.test.token-targets.timelock"))));

    function testVaultBeaconServesTheCurrentReceiptVaultOwnedByTheBoundTimelock() external {
        (, address vaultBeacon) = LibTestTokenEnvironment.deployBeacons(vm, TIMELOCK);
        assertEq(LibProdTokenTargets.vaultBeacon(), vaultBeacon, "vault beacon");
        assertEq(IBeacon(vaultBeacon).implementation(), LibProdDeployCurrent.STOX_RECEIPT_VAULT, "implementation");
        assertEq(Ownable(vaultBeacon).owner(), TIMELOCK, "owner");
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
        (, address beacon) = LibTestTokenEnvironment.deployBeacons(vm, TIMELOCK);
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
        (IAuthorizeV1 usAuthorizer, IAuthorizeV1 euAuthorizer) =
            LibTestTokenEnvironment.deploy(vm, TIMELOCK, US_OWNER, EU_OWNER);

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
