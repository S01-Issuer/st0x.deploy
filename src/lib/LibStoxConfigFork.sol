// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IConfigRegistryV3} from "rain-deploy-0.1.21/src/interface/IConfigRegistryV3.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.21/src/lib/LibConfigRegistryDeploy.sol";
import {
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.21/src/generated/candidate/ConfigRegistry.sol";

import {LibStoxConfig} from "./LibStoxConfig.sol";

/// @title LibStoxConfigFork
/// @notice `LibStoxConfig` bindings written by cheatcode, for a local EVM or a
/// fork: never on a live chain.
library LibStoxConfigFork {
    /// @notice Etches the pinned registry where it has no code.
    /// @param vm The cheatcode handle.
    function etchConfigRegistry(Vm vm) internal {
        if (LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.code.length == 0) {
            vm.etch(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, CONFIG_REGISTRY_RUNTIME_CODE);
        }
    }

    /// @notice Binds `name` to `value` as the root authority, a second after
    /// the name's last binding.
    /// @param vm The cheatcode handle.
    /// @param name The name.
    /// @param value The ABI-encoded value.
    function bind(Vm vm, bytes32 name, bytes memory value) internal {
        etchConfigRegistry(vm);
        vm.warp(block.timestamp + 1);
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        IConfigRegistryV3(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV3(LibStoxConfig.ROOT_AUTHORITY, name, value);
    }

    /// @notice Binds `LibStoxConfig.BEACON_OWNER` to `owner`.
    /// @param vm The cheatcode handle.
    /// @param owner The beacon owner.
    function bindBeaconOwner(Vm vm, address owner) internal {
        bind(vm, LibStoxConfig.BEACON_OWNER, abi.encode(owner));
    }

    /// @notice Binds `LibStoxConfig.AUTHORISER_ADMIN` to `admin`.
    /// @param vm The cheatcode handle.
    /// @param admin The authoriser admin.
    function bindAuthoriserAdmin(Vm vm, address admin) internal {
        bind(vm, LibStoxConfig.AUTHORISER_ADMIN, abi.encode(admin));
    }
}
