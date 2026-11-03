// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibRainDeploy} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    CREATION_CODE as CONFIG_REGISTRY_CREATION_CODE
} from "rain-deploy-0.1.29/src/generated/0_1_29/ConfigRegistry.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V8_ADDRESS,
    CREATION_CODE as CLONE_FACTORY_V8_CREATION_CODE
} from "rain-factory-deploy-0.2.5/src/generated/0_2_5/CloneFactory.sol";
import {CloneFactory} from "rain-factory-deploy-0.2.5/src/concrete/CloneFactory.sol";
import {IAuthorizeV1} from "rain-vats-0.2.16/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE
} from "rain-vats-0.2.16/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.16/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {StoxCorporateActionsFacet} from "../../src/concrete/StoxCorporateActionsFacet.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibProdDeployV4 as V4} from "../../src/generated/LibProdDeployV4.sol";
import {IST0xVaultBeaconSet} from "../../src/interface/IST0xVaultBeaconSet.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "./LibTestDeploy.sol";

/// @title LibTestTokenEnvironment
/// @notice What production tokens deploy into on the local EVM: the frozen
/// 0.1.1 beacon set serving the candidate implementations, the V8 clone
/// factory and ConfigRegistry, and the root authority's beacon and RBAC
/// bindings.
library LibTestTokenEnvironment {
    /// The frozen 0.1.1 beacon-set deployer at its Zoltu address.
    function deployVaultBeaconSet(Vm vm) internal returns (IST0xVaultBeaconSet) {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(V4.STOX_RECEIPT_CREATION_CODE_0_1_1);
        LibRainDeploy.deployZoltu(V4.STOX_RECEIPT_VAULT_CREATION_CODE_0_1_1);
        address deployer =
            LibRainDeploy.deployZoltu(V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_1);
        require(deployer == V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1, "beacon set deployer");
        return IST0xVaultBeaconSet(deployer);
    }

    function deployFactoryAndRegistry() internal {
        require(LibRainDeploy.deployZoltu(CLONE_FACTORY_V8_CREATION_CODE) == CLONE_FACTORY_V8_ADDRESS, "factory");
        require(LibRainDeploy.deployZoltu(CONFIG_REGISTRY_CREATION_CODE) == CONFIG_REGISTRY_ADDRESS, "registry");
    }

    function upgrade(Vm vm, address beacon, address implementation) internal {
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

    function bindRbac(Vm vm, bytes32 name, address owner, IAuthorizeV1 authorizer) internal {
        LibTestDeploy.bind(
            vm,
            LibStoxConfig.ROOT_AUTHORITY,
            name,
            OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE,
            abi.encode(OffchainAssetReceiptVaultRbacV1({owner: owner, authorizer: authorizer}))
        );
    }

    /// @return The US and EU authorizers, administered by `usOwner` and `euOwner`.
    function deploy(Vm vm, address usOwner, address euOwner) internal returns (IAuthorizeV1, IAuthorizeV1) {
        IST0xVaultBeaconSet set = deployVaultBeaconSet(vm);
        LibTestDeploy.deployImplementations(vm);
        LibRainDeploy.deployZoltu(type(StoxCorporateActionsFacet).creationCode);
        upgrade(vm, address(set.iReceiptBeacon()), V4.STOX_RECEIPT_CANDIDATE);
        upgrade(vm, address(set.iOffchainAssetReceiptVaultBeacon()), V4.STOX_RECEIPT_VAULT_CANDIDATE);
        deployFactoryAndRegistry();
        IAuthorizeV1 usAuthorizer = newAuthorizer(usOwner);
        IAuthorizeV1 euAuthorizer = newAuthorizer(euOwner);
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
        bindRbac(vm, LibStoxConfig.RBAC_US_NAME, usOwner, usAuthorizer);
        bindRbac(vm, LibStoxConfig.RBAC_EU_NAME, euOwner, euAuthorizer);
        return (usAuthorizer, euAuthorizer);
    }
}
