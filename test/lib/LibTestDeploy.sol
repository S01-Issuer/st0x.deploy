// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibRainDeploy} from "rain-deploy-0.1.20/src/lib/LibRainDeploy.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.20/src/generated/0_1_20/ConfigRegistry.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_ADDRESS,
    RUNTIME_CODE as CLONE_FACTORY_RUNTIME_CODE
} from "rain-factory-deploy-0.2.1/src/generated/0_2_1/CloneFactory.sol";
import {ICloneableFactoryV5} from "rain-factory-0.2.4/src/interface/ICloneableFactoryV5.sol";
import {IConfigRegistryV2} from "rain-deploy-0.1.20/src/interface/IConfigRegistryV2.sol";
import {IAuthorizeV1} from "rain-vats-0.2.6-pr345/src/interface/IAuthorizeV1.sol";
import {OffchainAssetReceiptVaultRbacV1} from "rain-vats-0.2.6-pr345/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {
    CONFIG_REGISTRY_OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V1_TAG,
    ConfigRegistryOffchainAssetReceiptVaultConfigV1
} from "rain-vats-0.2.6-pr345/src/interface/IConfigRegistryOffchainAssetReceiptVaultV1.sol";
import {
    CONFIG_REGISTRY_RBAC_MIN_AGE
} from "rain-vats-0.2.6-pr345/src/concrete/vault/ConfigRegistryOffchainAssetReceiptVault.sol";
import {LibProdDeployV1} from "../../src/lib/LibProdDeployV1.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {StoxReceipt} from "../../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../../src/concrete/StoxWrappedTokenVault.sol";

/// @title LibTestDeploy
/// @notice The production token set on the local EVM: the candidate
/// implementations at their Zoltu addresses, served by the V1 beacons at their
/// production addresses, with the pinned V5 clone factory and ConfigRegistry
/// in place. Tokens are factory beacon proxies, as in production.
library LibTestDeploy {
    /// Zoltu-deploys the candidate receipt, vault and wrapper implementations,
    /// refusing any that lands off its pinned address.
    function deployImplementations(Vm vm) internal {
        LibRainDeploy.etchZoltuFactory(vm);
        address receipt = LibRainDeploy.deployZoltu(type(StoxReceipt).creationCode);
        require(receipt == LibProdDeployV4.STOX_RECEIPT_CANDIDATE, "StoxReceipt address mismatch");
        address receiptVault = LibRainDeploy.deployZoltu(type(StoxReceiptVault).creationCode);
        require(receiptVault == LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE, "StoxReceiptVault address mismatch");
        address wrapper = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        require(wrapper == LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_CANDIDATE, "StoxWrappedTokenVault address mismatch");
    }

    /// Places an `UpgradeableBeacon` serving `implementation`, owned by
    /// `owner`, at `at`: its code, then its owner and implementation slots.
    function placeBeacon(Vm vm, address at, address implementation, address owner) internal {
        UpgradeableBeacon beacon = new UpgradeableBeacon(implementation, owner);
        vm.etch(at, address(beacon).code);
        vm.store(at, bytes32(uint256(0)), vm.load(address(beacon), bytes32(uint256(0))));
        vm.store(at, bytes32(uint256(1)), vm.load(address(beacon), bytes32(uint256(1))));
    }

    /// The candidate implementations behind the V1 receipt, vault and wrapper
    /// beacons, and the pinned clone factory and ConfigRegistry, on a local EVM
    /// that is Base, the chain the V1 beacons serve.
    function deployAll(Vm vm) internal {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        deployImplementations(vm);
        address owner = LibProdDeployV1.BEACON_INITIAL_OWNER;
        placeBeacon(vm, LibProdDeployV1.STOX_RECEIPT_BEACON_V1, LibProdDeployV4.STOX_RECEIPT_CANDIDATE, owner);
        placeBeacon(
            vm, LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1, LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE, owner
        );
        placeBeacon(
            vm,
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_CANDIDATE,
            owner
        );
        vm.etch(CLONE_FACTORY_ADDRESS, CLONE_FACTORY_RUNTIME_CODE);
        vm.etch(CONFIG_REGISTRY_ADDRESS, CONFIG_REGISTRY_RUNTIME_CODE);
    }

    /// The pinned clone factory.
    function factory() internal pure returns (ICloneableFactoryV5) {
        return ICloneableFactoryV5(CLONE_FACTORY_ADDRESS);
    }

    /// A wrapper of `asset`: a factory beacon proxy over the V1 wrapper beacon.
    function newWrapper(address asset) internal returns (StoxWrappedTokenVault) {
        return StoxWrappedTokenVault(
            factory()
                .beaconProxyDeterministicOpenSalt(
                    LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1, abi.encode(asset), bytes32(0)
                )
        );
    }

    /// A token vault initialized from `data`: a factory beacon proxy over the
    /// V1 vault beacon.
    function newVault(bytes memory data) internal returns (StoxReceiptVault) {
        return StoxReceiptVault(
            payable(factory()
                    .beaconProxyDeterministicOpenSalt(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1, data, bytes32(0)))
        );
    }

    /// Binds `name` under `authority` to an RBAC of `owner`, Base's V1 receipt
    /// beacon and the single `authorizer`, then warps past the minimum age a
    /// vault requires.
    function bindRbac(Vm vm, address authority, bytes32 name, address owner, IAuthorizeV1 authorizer) internal {
        IAuthorizeV1[] memory authorizers = new IAuthorizeV1[](1);
        authorizers[0] = authorizer;
        vm.prank(authority);
        IConfigRegistryV2(CONFIG_REGISTRY_ADDRESS)
            .registerV2(
                authority,
                name,
                abi.encode(
                    OffchainAssetReceiptVaultRbacV1({
                    owner: owner,
                    receiptBeacon: IBeacon(LibProdDeployV1.STOX_RECEIPT_BEACON_V1),
                    authorizers: authorizers
                })
                )
            );
        vm.warp(block.timestamp + CONFIG_REGISTRY_RBAC_MIN_AGE + 1);
    }

    /// The init data of a vault named `name`, `symbol`, resolving its RBAC from
    /// `rbacName` under `authority`, with the first authorizer.
    function vaultData(string memory name, string memory symbol, address authority, bytes32 rbacName)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            CONFIG_REGISTRY_OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V1_TAG,
            ConfigRegistryOffchainAssetReceiptVaultConfigV1({
                name: name, symbol: symbol, authority: authority, rbacName: rbacName, authorizerIndex: 0, metadata: ""
            })
        );
    }
}
