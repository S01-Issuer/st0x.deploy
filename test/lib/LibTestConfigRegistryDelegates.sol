// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";

/// @title LibTestConfigRegistryDelegates
/// @notice The root's `ConfigRegistry` approvals of a delegate on a fork.
library LibTestConfigRegistryDelegates {
    IConfigRegistryV5 internal constant REGISTRY =
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);

    /// @notice The root approves `delegate` to bind `name` alone.
    function approve(Vm vm, bytes32 name, address delegate) internal {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        REGISTRY.approveV5(name, delegate);
    }

    /// @notice The root approves `delegate` to bind every name.
    function approveUnscoped(Vm vm, address delegate) internal {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        REGISTRY.approveUnscopedV5(delegate);
    }

    function revokeUnscoped(Vm vm, address delegate) internal {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        REGISTRY.revokeUnscopedV5(delegate);
    }
}
