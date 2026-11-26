// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {SafeBundleScript} from "rain-deploy-0.1.38/src/abstract/SafeBundleScript.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.38/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.38/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.38/src/lib/LibConfigRegistryDeploy.sol";
import {ConfigBinding} from "rain-deploy-0.1.38/src/lib/LibConfigRegistryRegister.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.38/src/lib/LibRegistryAuthority.sol";
import {LibRegistryDelegates} from "rain-deploy-0.1.38/src/lib/LibRegistryDelegates.sol";
import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";

import {StoxSafeBundleScript} from "../src/abstract/StoxSafeBundleScript.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibProdDeployCurrent} from "../src/generated/LibProdDeployCurrent.sol";
import {LibProdOrchestratorParams} from "../src/lib/LibProdOrchestratorParams.sol";
import {LibRootConfigBinding} from "../src/lib/LibRootConfigBinding.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The orchestrator beacon does not have its pinned runtime codehash.
/// @param beacon The beacon.
/// @param expected The pinned codehash.
/// @param actual The codehash on chain.
error OrchestratorBeaconCodehashMismatch(address beacon, bytes32 expected, bytes32 actual);

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

/// @notice This script's declaration on the root line, after the tQSEP
/// migration.
/// @return The declaration.
function bindOrchestratorConfigDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.BIND_ORCHESTRATOR_CONFIG,
        onto: LibStoxMigrations.QSEP_SET_FLEET_AUTHORISER,
        history: false
    });
}

/// @title BindOrchestratorConfig
/// @notice Authors the per-chain Safe bundle that binds
/// `LibStoxConfig.ORCHESTRATOR_BEACON_NAME` to the orchestrator proxy's beacon
/// and `LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME` to
/// `LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK` under the root authority, as
/// the root's approved delegate, and records it. On 0G the bundle is the
/// record alone: no current-source orchestrator deploys there to read the
/// bindings.
contract BindOrchestratorConfig is StoxSafeBundleScript, IStoxScript {
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
        return string.concat("out/20261113-bind-orchestrator-config-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        if (block.chainid == LibSafeInvariants.ZEROG_CHAIN_ID) {
            preflightZerog();
            return;
        }
        LibConfigRegistry.checkCodeHash();
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, chainSafe);
        address beacon = LibProdOrchestratorParams.orchestratorParams().beacon;
        if (beacon.codehash != LibProdDeployCurrent.ST0X_ORCHESTRATOR_BEACON_CODEHASH) {
            revert OrchestratorBeaconCodehashMismatch(
                beacon, LibProdDeployCurrent.ST0X_ORCHESTRATOR_BEACON_CODEHASH, beacon.codehash
            );
        }

        LibStoxMigrations.assertNext(bindOrchestratorConfigDeclaration(), chainSafe);
        assertDelegate(LibStoxConfig.ORCHESTRATOR_BEACON_NAME, chainSafe);
        assertDelegate(LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME, chainSafe);
    }

    /// @notice 0G's pre-flight: the Safe, 0G's timelock and the line, then
    /// `assertNothingToBindOnZerog`.
    function preflightZerog() internal view {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(LibTimelockInvariants.timelockForChainId(block.chainid), chainSafe);
        LibStoxMigrations.assertNext(bindOrchestratorConfigDeclaration(), chainSafe);
        assertNothingToBindOnZerog();
    }

    /// @notice Reverts unless both names are unbound under the root, and the
    /// orchestrator beacon and the suite timelock they would name have no code
    /// on this chain.
    function assertNothingToBindOnZerog() internal view {
        LibRootConfigBinding.assertUnbound(LibStoxConfig.ORCHESTRATOR_BEACON_NAME);
        LibRootConfigBinding.assertUnbound(LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME);
        LibStoxDeployNetworks.assertUndeployed(LibProdOrchestratorParams.orchestratorParams().beacon);
        LibStoxDeployNetworks.assertUndeployed(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
    }

    function assertDelegate(bytes32 name, address chainSafe) internal view {
        IConfigRegistryV5 registry = IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        if (!LibRegistryDelegates.approved(registry, LibRegistryAuthority.ROOT_AUTHORITY, name, chainSafe)) {
            revert SafeNotOrchestratorConfigDelegate(name, chainSafe);
        }
    }

    /// @notice The orchestrator proxy's beacon as an `address`.
    function beaconBinding() internal pure returns (ConfigBinding memory) {
        return ConfigBinding("", "address", abi.encode(LibProdOrchestratorParams.orchestratorParams().beacon), "");
    }

    /// @notice `LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK` as an `address`.
    function initialAdminBinding() internal pure returns (ConfigBinding memory) {
        return ConfigBinding("", "address", abi.encode(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK), "");
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        if (block.chainid == LibSafeInvariants.ZEROG_CHAIN_ID) {
            return LibStoxMigrations.recordOnlyBundle(bindOrchestratorConfigDeclaration());
        }
        SafeTx[] memory txs = new SafeTx[](3);
        txs[0] = LibRootConfigBinding.registerTx(LibStoxConfig.ORCHESTRATOR_BEACON_NAME, beaconBinding());
        txs[1] = LibRootConfigBinding.registerTx(LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME, initialAdminBinding());
        txs[2] = LibStoxMigrations.recordTx(bindOrchestratorConfigDeclaration());
        return txs;
    }

    function assertBound(bytes32 name, ConfigBinding memory binding) internal view {
        (bool bound, bytes memory value, uint256 registeredAt) = LibRootConfigBinding.boundThisBlock(name, binding);
        if (!bound) revert OrchestratorConfigBindingMismatch(name, value, registeredAt);
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        if (block.chainid == LibSafeInvariants.ZEROG_CHAIN_ID) {
            LibStoxMigrations.assertRecorded(bindOrchestratorConfigDeclaration());
            LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
            assertNothingToBindOnZerog();
            return;
        }
        assertBound(LibStoxConfig.ORCHESTRATOR_BEACON_NAME, beaconBinding());
        assertBound(LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME, initialAdminBinding());
        LibStoxMigrations.assertRecorded(bindOrchestratorConfigDeclaration());
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }
}
