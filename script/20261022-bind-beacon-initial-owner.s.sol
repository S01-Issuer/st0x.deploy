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
import {LibRootConfigBinding} from "../src/lib/LibRootConfigBinding.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../src/lib/LibStoxConfig.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The root authority has not approved the Safe to bind the
/// beacon initial owner.
/// @param safe The Safe.
error SafeNotBeaconInitialOwnerDelegate(address safe);

/// @notice After the bundle, the beacon initial owner binding is not
/// `LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK` bound in this block.
/// @param value The bound value.
/// @param registeredAt When it was bound.
error BeaconInitialOwnerBindingMismatch(bytes value, uint256 registeredAt);

/// @notice This script's declaration on the root line, after the 0G
/// orchestrator roles' execution record, which follows their schedule and the
/// 0G token creation.
/// @return The declaration.
function bindBeaconInitialOwnerDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.BIND_BEACON_INITIAL_OWNER,
        onto: LibStoxMigrations.EXECUTE_ZEROG_ORCHESTRATOR_ROLES,
        history: false
    });
}

/// @title BindBeaconInitialOwner
/// @notice Authors the per-chain Safe bundle that binds
/// `LibStoxConfig.BEACON_INITIAL_OWNER_NAME` under the root authority to
/// `LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK`, as the root's approved
/// delegate, and records it. On 0G the bundle is the record alone: the
/// binding is read only by the constructor of a current-source beacon, and no
/// current-source suite deploys on 0G (`StoxDeploySuites.setCandidateNetworks`).
/// The 0G arm requires the name still unbound there, so no such beacon can be
/// deployed, and the suite timelock the binding names still without code.
contract BindBeaconInitialOwner is StoxSafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return bindBeaconInitialOwnerDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x: bind the beacon initial owner";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261022-bind-beacon-initial-owner-", vm.toString(block.chainid), ".json");
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

        LibStoxMigrations.assertNext(bindBeaconInitialOwnerDeclaration(), chainSafe);
        IConfigRegistryV5 registry = IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        if (!LibRegistryDelegates.approved(
                registry, LibRegistryAuthority.ROOT_AUTHORITY, LibStoxConfig.BEACON_INITIAL_OWNER_NAME, chainSafe
            )) {
            revert SafeNotBeaconInitialOwnerDelegate(chainSafe);
        }
    }

    /// @notice 0G's pre-flight: the Safe, 0G's timelock and the line, then
    /// `assertNothingToBindOnZerog`.
    function preflightZerog() internal view {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(LibTimelockInvariants.timelockForChainId(block.chainid), chainSafe);
        LibStoxMigrations.assertNext(bindBeaconInitialOwnerDeclaration(), chainSafe);
        assertNothingToBindOnZerog();
    }

    /// @notice Reverts unless the name is unbound under the root and the suite
    /// timelock it would name has no code on this chain.
    function assertNothingToBindOnZerog() internal view {
        LibRootConfigBinding.assertUnbound(LibStoxConfig.BEACON_INITIAL_OWNER_NAME);
        LibStoxMigrations.assertNoCurrentSourceOnZerog(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
    }

    /// @notice `LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK` as an `address`.
    function timelockBinding() internal pure returns (ConfigBinding memory) {
        return ConfigBinding("", "address", abi.encode(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK), "");
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        if (block.chainid == LibSafeInvariants.ZEROG_CHAIN_ID) {
            SafeTx[] memory record = new SafeTx[](1);
            record[0] = LibStoxMigrations.recordTx(bindBeaconInitialOwnerDeclaration());
            return record;
        }
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = LibRootConfigBinding.registerTx(LibStoxConfig.BEACON_INITIAL_OWNER_NAME, timelockBinding());
        txs[1] = LibStoxMigrations.recordTx(bindBeaconInitialOwnerDeclaration());
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        if (block.chainid == LibSafeInvariants.ZEROG_CHAIN_ID) {
            LibStoxMigrations.assertRecorded(bindBeaconInitialOwnerDeclaration());
            LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
            assertNothingToBindOnZerog();
            return;
        }
        (bool bound, bytes memory value, uint256 registeredAt) =
            LibRootConfigBinding.boundThisBlock(LibStoxConfig.BEACON_INITIAL_OWNER_NAME, timelockBinding());
        if (!bound) revert BeaconInitialOwnerBindingMismatch(value, registeredAt);
        LibStoxMigrations.assertRecorded(bindBeaconInitialOwnerDeclaration());
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }
}
