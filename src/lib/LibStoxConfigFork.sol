// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";
import {
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.30/src/generated/candidate/ConfigRegistry.sol";

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

    /// @notice Binds `name` to `value` as `valueType` under the root
    /// authority, a second after the name's last binding.
    /// @param vm The cheatcode handle.
    /// @param name The name.
    /// @param valueType The ABI type of `value`.
    /// @param value The ABI-encoded value.
    function bind(Vm vm, bytes32 name, string memory valueType, bytes memory value) internal {
        etchConfigRegistry(vm);
        vm.warp(block.timestamp + 1);
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV5(LibStoxConfig.ROOT_AUTHORITY, name, valueType, value, "");
    }

    /// @notice Binds `LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME` to `admin`.
    /// @param vm The cheatcode handle.
    /// @param admin The authoriser initial admin.
    function bindAuthoriserInitialAdmin(Vm vm, address admin) internal {
        bind(vm, LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME, "address", abi.encode(admin));
    }
}
