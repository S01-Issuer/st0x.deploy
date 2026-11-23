// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_ADDRESS,
    RUNTIME_CODE as CLONE_FACTORY_RUNTIME_CODE
} from "rain-factory-deploy-0.2.8/src/generated/0_2_5/CloneFactory.sol";
import {ICloneableFactoryV7} from "rain-factory-0.2.11/src/interface/ICloneableFactoryV7.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {IAuthorizeV1} from "rain-vats-0.2.20/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE
} from "rain-vats-0.2.20/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
    OffchainAssetReceiptVaultConfigV3
} from "rain-vats-0.2.20/src/interface/IOffchainAssetReceiptVaultV1.sol";
import {
    OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CONFIG_V2_TAG,
    OffchainAssetReceiptVaultAuthorizerV1ConfigV2
} from "rain-vats-0.2.20/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibProdDeployV1} from "../../src/lib/LibProdDeployV1.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {StoxReceipt} from "../../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../../src/concrete/StoxWrappedTokenVault.sol";
import {IStoxUnderlyingV1} from "../../src/interface/IStoxUnderlyingV1.sol";
import {LibAssetId} from "../../src/lib/LibAssetId.sol";

/// @title LibTestDeploy
/// @notice The production token set on the local EVM: the candidate
/// implementations at their Zoltu addresses, served by the V1 beacons at their
/// production addresses, with the pinned V7 clone factory and ConfigRegistry
/// in place. Tokens are registry beacon proxies, as in production.
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
        etchConfigRegistry(vm);
    }

    /// The pinned ConfigRegistry at its address.
    function etchConfigRegistry(Vm vm) internal {
        vm.etch(CONFIG_REGISTRY_ADDRESS, CONFIG_REGISTRY_RUNTIME_CODE);
    }

    /// The pinned ConfigRegistry, with the root authority binding the
    /// orchestrator initial admin to `admin`.
    function bindOrchestratorInitialAdmin(Vm vm, address admin) internal {
        etchConfigRegistry(vm);
        bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME,
            "address",
            abi.encode(admin)
        );
    }

    /// The pinned ConfigRegistry, with the root authority binding the beacon
    /// initial owner to `owner`.
    function bindBeaconInitialOwner(Vm vm, address owner) internal {
        etchConfigRegistry(vm);
        bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.BEACON_INITIAL_OWNER_NAME,
            "address",
            abi.encode(owner)
        );
    }

    bytes32 internal constant AUTHORIZER_INITIAL_ADMIN_NAME = keccak256("st0x.test.authorizer-initial-admin");

    /// The pinned ConfigRegistry, with the root authority binding the
    /// authorizer initial admin to `admin`.
    /// @return The authorizer init data naming that binding.
    function authorizerData(Vm vm, address admin) internal returns (bytes memory) {
        etchConfigRegistry(vm);
        bind(vm, LibRegistryAuthority.ROOT_AUTHORITY, AUTHORIZER_INITIAL_ADMIN_NAME, "address", abi.encode(admin));
        return authorizerConfig(LibRegistryAuthority.ROOT_AUTHORITY, AUTHORIZER_INITIAL_ADMIN_NAME);
    }

    /// The authorizer init data naming `name` under `authority`.
    function authorizerConfig(address authority, bytes32 name) internal pure returns (bytes memory) {
        return abi.encode(
            OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CONFIG_V2_TAG,
            OffchainAssetReceiptVaultAuthorizerV1ConfigV2({authority: authority, initialAdminName: name})
        );
    }

    /// The pinned clone factory.
    function factory() internal pure returns (ICloneableFactoryV7) {
        return ICloneableFactoryV7(CLONE_FACTORY_ADDRESS);
    }

    /// A wrapper of `asset`: a registry beacon proxy over the wrapper beacon
    /// `authority` binds, so it has the same address wherever `asset` does.
    function newWrapper(address authority, address asset) internal returns (StoxWrappedTokenVault) {
        return StoxWrappedTokenVault(
            factory()
                .registryBeaconProxy(
                    CONFIG_REGISTRY_ADDRESS, authority, LibStoxConfig.WRAPPER_BEACON_NAME, abi.encode(asset), bytes32(0)
                )
        );
    }

    /// A token vault initialized from `data`: a registry beacon proxy over the
    /// vault beacon `authority` binds.
    function newVault(address authority, bytes memory data) internal returns (StoxReceiptVault) {
        return StoxReceiptVault(
            payable(factory()
                    .registryBeaconProxy(
                        CONFIG_REGISTRY_ADDRESS, authority, LibStoxConfig.VAULT_BEACON_NAME, data, bytes32(0)
                    ))
        );
    }

    /// Binds the vault, receipt and wrapper beacon names under `authority` to
    /// Base's V1 beacons.
    function bindBeacons(Vm vm, address authority) internal {
        bind(
            vm,
            authority,
            LibStoxConfig.VAULT_BEACON_NAME,
            "address",
            abi.encode(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1)
        );
        bind(
            vm,
            authority,
            LibStoxConfig.RECEIPT_BEACON_NAME,
            "address",
            abi.encode(LibProdDeployV1.STOX_RECEIPT_BEACON_V1)
        );
        bind(
            vm,
            authority,
            LibStoxConfig.WRAPPER_BEACON_NAME,
            "address",
            abi.encode(LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1)
        );
    }

    /// Binds the beacon names, and `name` under `authority` to an RBAC of
    /// `owner` and `authorizer`.
    function bindRbac(Vm vm, address authority, bytes32 name, address owner, IAuthorizeV1 authorizer) internal {
        bindBeacons(vm, authority);
        bind(
            vm,
            authority,
            name,
            OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE,
            abi.encode(OffchainAssetReceiptVaultRbacV1({owner: owner, authorizer: authorizer}))
        );
    }

    /// The clock moves a second before each bind, since the registry refuses a
    /// rebind at the moment of the binding it replaces.

    function bind(Vm vm, address authority, bytes32 name, string memory valueType, bytes memory value) internal {
        vm.warp(block.timestamp + 1);
        vm.prank(authority);
        IConfigRegistryV5(CONFIG_REGISTRY_ADDRESS).registerV5(authority, name, valueType, value, "");
    }

    /// The init data of a nameless vault with asset id `assetId`, resolving its
    /// RBAC from `rbacName` under `authority`, with its receipt from
    /// `LibStoxConfig.RECEIPT_BEACON_NAME`. The vault rejects any init with a
    /// name or symbol; `newNamedVault` sets them after deploy.
    function vaultData(string memory assetId, address authority, bytes32 rbacName)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
            OffchainAssetReceiptVaultConfigV3({
                name: "",
                symbol: "",
                authority: authority,
                rbacName: rbacName,
                receiptBeaconName: LibStoxConfig.RECEIPT_BEACON_NAME,
                metadata: LibAssetId.encodeMetadata(assetId)
            })
        );
    }

    /// `newVault`, then `owner` sets its underlying `ticker` and `underlyingName`,
    /// so it reports "t" + `ticker` and `underlyingName` + " (ST0x)".
    function newNamedVault(
        Vm vm,
        address authority,
        bytes memory data,
        address owner,
        string memory ticker,
        string memory underlyingName
    ) internal returns (StoxReceiptVault) {
        StoxReceiptVault vault = newVault(authority, data);
        vm.prank(owner);
        IStoxUnderlyingV1(address(vault)).setUnderlying(ticker, underlyingName);
        return vault;
    }
}
