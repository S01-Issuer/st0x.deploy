// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.37/src/lib/LibConfigRegistryDeploy.sol";
import {ConfigBinding, LibConfigRegistryRegister} from "rain-deploy-0.1.37/src/lib/LibConfigRegistryRegister.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.37/src/lib/LibRegistryAuthority.sol";
import {SafeTx} from "rain-deploy-0.1.37/src/lib/LibSafeTx.sol";

/// @title LibRootConfigBinding
/// @notice Binds config names under `LibRegistryAuthority.ROOT_AUTHORITY` in
/// the config registry, and checks the binding a bundle wrote.
library LibRootConfigBinding {
    /// @notice The bundle entry that binds `name` to `binding` under the root.
    /// @param name The config name.
    /// @param binding The binding.
    /// @return The CALL that writes the binding.
    function registerTx(bytes32 name, ConfigBinding memory binding) internal pure returns (SafeTx memory) {
        return SafeTx({
            to: LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            value: 0,
            data: LibConfigRegistryRegister.registerCalldata(LibRegistryAuthority.ROOT_AUTHORITY, name, binding),
            operation: Enum.Operation.Call
        });
    }

    /// @notice Whether `name` is bound under the root to `binding` in this
    /// block, with what it is bound to and when.
    /// @param name The config name.
    /// @param binding The expected binding.
    /// @return Whether it is bound to `binding` in this block.
    /// @return The bound value.
    /// @return When it was bound.
    function boundThisBlock(bytes32 name, ConfigBinding memory binding)
        internal
        view
        returns (bool, bytes memory, uint256)
    {
        (bytes memory value, uint256 registeredAt, bytes32 typeHash) =
            LibConfigRegistryRegister.currentBinding(LibRegistryAuthority.ROOT_AUTHORITY, name);
        // slither-disable-start incorrect-equality
        // forge-lint: disable-next-line(block-timestamp)
        bool bound = LibConfigRegistryRegister.isBound(value, typeHash, binding) && registeredAt == block.timestamp;
        // slither-disable-end incorrect-equality
        return (bound, value, registeredAt);
    }
}
