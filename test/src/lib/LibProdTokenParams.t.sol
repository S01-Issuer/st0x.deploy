// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {DeployDependency, LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V8_ADDRESS
} from "rain-factory-deploy-0.2.8/src/generated/0_2_5/CloneFactory.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyParams
} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {IAuthorizeV1} from "rain-vats-0.2.20/src/interface/IAuthorizeV1.sol";

import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {LibProdDeployCurrent} from "../../../src/generated/LibProdDeployCurrent.sol";
import {LibStoxTokenProxy} from "../../../src/generated/LibStoxTokenProxy.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenParams} from "../../../src/lib/LibProdTokenParams.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {StoxTokenConfigV1, STOX_TOKEN_CONFIG_V1_TAG} from "../../../src/interface/IStoxTokenConfigV1.sol";
import {ST0X_NAME_SUFFIX} from "../../../src/lib/LibUnderlying.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTestTokenEnvironment} from "../../lib/LibTestTokenEnvironment.sol";
import {LibTestTokenRows} from "../../lib/LibTestTokenRows.sol";

/// @title LibProdTokenParamsTest
/// @notice One V8 registry beacon proxy per token row, production and test alike; each row's deploy step lands its
/// token.
contract LibProdTokenParamsTest is Test {
    address internal constant US_OWNER = address(uint160(uint256(keccak256("st0x.test.token-params.us-owner"))));
    address internal constant EU_OWNER = address(uint160(uint256(keccak256("st0x.test.token-params.eu-owner"))));
    address internal constant DEPLOYER = address(uint160(uint256(keccak256("st0x.test.token-params.deployer"))));
    address internal constant TIMELOCK = address(uint160(uint256(keccak256("st0x.test.token-params.timelock"))));

    function testVaultBeaconServesTheCurrentReceiptVaultOwnedByTheBoundTimelock() external {
        (, address vaultBeacon) = LibTestTokenEnvironment.deployBeacons(vm, TIMELOCK);
        assertEq(LibProdTokenParams.vaultBeacon(), vaultBeacon, "vault beacon");
        assertEq(IBeacon(vaultBeacon).implementation(), LibProdDeployCurrent.STOX_RECEIPT_VAULT, "implementation");
        assertEq(Ownable(vaultBeacon).owner(), TIMELOCK, "owner");
    }

    function testEachParamsIsARegistryBeaconProxyOfItsRowOverTheRootVaultBeacon() external pure {
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        RegistryBeaconProxyParams[] memory params = LibProdTokenParams.tokenParams(configs);
        assertEq(params.length, configs.length, "one params per row");
        for (uint256 i = 0; i < params.length; i++) {
            assertEq(params[i].factory, CLONE_FACTORY_V8_ADDRESS, configs[i].underlying);
            assertEq(params[i].registry, CONFIG_REGISTRY_ADDRESS, configs[i].underlying);
            assertEq(params[i].authority, LibRegistryAuthority.ROOT_AUTHORITY, configs[i].underlying);
            assertEq(params[i].beaconName, LibStoxConfig.VAULT_BEACON_NAME, configs[i].underlying);
            assertEq(params[i].beacon, LibProdTokenParams.vaultBeacon(), configs[i].underlying);
            assertEq(params[i].salt, bytes32(0), configs[i].underlying);
        }
    }

    function testEachParamsDataIsTheCanonicalStoxTokenConfigV1OfItsRow() external pure {
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        RegistryBeaconProxyParams[] memory params = LibProdTokenParams.tokenParams(configs);
        for (uint256 i = 0; i < params.length; i++) {
            (bytes32 tag, StoxTokenConfigV1 memory config) = abi.decode(params[i].data, (bytes32, StoxTokenConfigV1));
            assertEq(abi.encode(tag, config), params[i].data, "canonical");
            assertEq(tag, STOX_TOKEN_CONFIG_V1_TAG, "tag");
            assertEq(config.assetId, configs[i].assetId, "asset id");
            assertEq(config.listingTicker, configs[i].listingTicker, "listing ticker");
            assertEq(config.listingName, configs[i].listingName, "listing name");
            assertEq(uint8(config.region), uint8(configs[i].region), "region");
            assertEq(config.authority, LibRegistryAuthority.ROOT_AUTHORITY, "authority");
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
        RegistryBeaconProxyParams[] memory params = LibProdTokenParams.tokenParams(LibTestTokenRows.allRows());
        for (uint256 i = 0; i < params.length; i++) {
            address proxy = LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(params[i]);
            for (uint256 j = 0; j < i; j++) {
                assertNotEq(LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(params[j]), proxy);
            }
        }
    }

    function testParamsAreTheSameOnEveryDeploymentNetwork() external {
        bytes memory baseline = abi.encode(LibProdTokenParams.tokenParams(LibTestTokenRows.allRows()));
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 n = 0; n < networks.length; n++) {
            vm.chainId(networks[n].chainId);
            assertEq(abi.encode(LibProdTokenParams.tokenParams(LibTestTokenRows.allRows())), baseline, networks[n].name);
        }
    }

    function testDependenciesAreTheV8FactoryRegistryAndVaultBeaconAsDeployed() external {
        (, address beacon) = LibTestTokenEnvironment.deployBeacons(vm, TIMELOCK);
        DeployDependency[] memory deps = LibProdTokenParams.tokenDependencies();
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

        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        uint256 snapshotRows = LibProdTokenConfig.productionTokenConfigs().length;
        RegistryBeaconProxyParams[] memory params = LibProdTokenParams.tokenParams(configs);
        for (uint256 i = 0; i < params.length; i++) {
            address deployed = LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployStep(
                vm, "base", DEPLOYER, abi.encode(params[i])
            );
            assertEq(
                deployed, LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(params[i]), "address"
            );
            assertEq(deployed.code, LibStoxTokenProxy.RUNTIME_CODE, "runtime code");

            StoxReceiptVault token = StoxReceiptVault(payable(deployed));
            bool us = configs[i].region == Region.US;
            bool inSnapshot = i < snapshotRows;
            assertEq(
                token.name(),
                string.concat(inSnapshot ? configs[i].underlyingName : configs[i].listingName, ST0X_NAME_SUFFIX),
                "name"
            );
            assertEq(
                token.symbol(), string.concat("t", inSnapshot ? configs[i].ticker : configs[i].listingTicker), "symbol"
            );
            assertEq(token.owner(), us ? US_OWNER : EU_OWNER, "owner");
            assertEq(address(token.authorizer()), address(us ? usAuthorizer : euAuthorizer), "authorizer");
        }
    }
}
