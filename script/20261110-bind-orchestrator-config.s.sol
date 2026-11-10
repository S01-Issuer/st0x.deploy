// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";
import {ConfigBinding, LibConfigRegistryRegister} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryRegister.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibProdOrchestratorParams} from "../src/lib/LibProdOrchestratorParams.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../src/lib/LibStoxConfig.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The root authority has not approved the Safe to bind an
/// orchestrator config name.
/// @param name The name.
/// @param safe The Safe.
error SafeNotOrchestratorConfigDelegate(bytes32 name, address safe);

/// @notice After the bundle, an orchestrator config name is not bound to its
/// expected value in this block.
/// @param name The name.
/// @param value The bound value.
/// @param registeredAt When it was bound.
error OrchestratorConfigBindingMismatch(bytes32 name, bytes value, uint256 registeredAt);

/// @notice This script's declaration on the root line, after the
/// backfill record.
/// @return The declaration.
function bindOrchestratorConfigDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.BIND_ORCHESTRATOR_CONFIG,
        onto: LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5,
        history: false
    });
}

/// @title BindOrchestratorConfig
/// @notice Authors the per-chain Safe bundle that binds
/// `LibStoxConfig.ORCHESTRATOR_BEACON_NAME` to the orchestrator proxy's beacon
/// and `LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME` to the chain's
/// governance timelock under the root authority, as the root's approved
/// delegate, and records it.
contract BindOrchestratorConfig is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return bindOrchestratorConfigDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x: bind the orchestrator config";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261110-bind-orchestrator-config-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        LibConfigRegistry.checkCodeHash();
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);

        LibStoxMigrations.assertNext(bindOrchestratorConfigDeclaration(), chainSafe);
        assertDelegate(LibStoxConfig.ORCHESTRATOR_BEACON_NAME, chainSafe);
        assertDelegate(LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME, chainSafe);
    }

    function assertDelegate(bytes32 name, address chainSafe) internal view {
        if (!IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
                .approvedV5(LibRegistryAuthority.ROOT_AUTHORITY, name, chainSafe)) {
            revert SafeNotOrchestratorConfigDelegate(name, chainSafe);
        }
    }

    /// @notice The orchestrator proxy's beacon as an `address`.
    function beaconBinding() internal pure returns (ConfigBinding memory) {
        return ConfigBinding("", "address", abi.encode(LibProdOrchestratorParams.orchestratorParams().beacon), "");
    }

    /// @notice The chain's governance timelock as an `address`.
    function initialAdminBinding() internal view returns (ConfigBinding memory) {
        return ConfigBinding("", "address", abi.encode(LibTimelockInvariants.timelockForChainId(block.chainid)), "");
    }

    function registerTx(bytes32 name, ConfigBinding memory binding) internal pure returns (SafeTx memory) {
        return SafeTx({
            to: LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            value: 0,
            data: LibConfigRegistryRegister.registerCalldata(LibRegistryAuthority.ROOT_AUTHORITY, name, binding),
            operation: Enum.Operation.Call
        });
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        SafeTx[] memory txs = new SafeTx[](3);
        txs[0] = registerTx(LibStoxConfig.ORCHESTRATOR_BEACON_NAME, beaconBinding());
        txs[1] = registerTx(LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME, initialAdminBinding());
        txs[2] = LibStoxMigrations.recordTx(bindOrchestratorConfigDeclaration());
        return txs;
    }

    function assertBound(bytes32 name, ConfigBinding memory binding) internal view {
        (bytes memory value, uint256 registeredAt, bytes32 typeHash) =
            LibConfigRegistryRegister.currentBinding(LibRegistryAuthority.ROOT_AUTHORITY, name);
        // forge-lint: disable-next-line(block-timestamp)
        if (!LibConfigRegistryRegister.isBound(value, typeHash, binding) || registeredAt != block.timestamp) {
            revert OrchestratorConfigBindingMismatch(name, value, registeredAt);
        }
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        assertBound(LibStoxConfig.ORCHESTRATOR_BEACON_NAME, beaconBinding());
        assertBound(LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME, initialAdminBinding());
        LibStoxMigrations.assertRecorded(bindOrchestratorConfigDeclaration());
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }
}
