// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibProdDeployCurrent} from "../src/generated/LibProdDeployCurrent.sol";
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

/// @notice This script's declaration on the root line, after the
/// backfill record.
/// @return The declaration.
function bindBeaconInitialOwnerDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.BIND_BEACON_INITIAL_OWNER,
        onto: LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5,
        history: false
    });
}

/// @title BindBeaconInitialOwner
/// @notice Authors the per-chain Safe bundle that binds
/// `LibStoxConfig.BEACON_INITIAL_OWNER_NAME` under the root authority to
/// `LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK`, as the root's approved
/// delegate, and records it.
contract BindBeaconInitialOwner is SafeBundleScript, IStoxScript {
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
        LibConfigRegistry.checkCodeHash();
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, chainSafe);

        LibStoxMigrations.assertNext(bindBeaconInitialOwnerDeclaration(), chainSafe);
        if (!IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
                .approvedV5(LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_INITIAL_OWNER_NAME, chainSafe)) {
            revert SafeNotBeaconInitialOwnerDelegate(chainSafe);
        }
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address timelock = LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK;
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({
            to: LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            value: 0,
            data: abi.encodeCall(
                IConfigRegistryV5.registerV5,
                (
                    LibStoxConfig.ROOT_AUTHORITY,
                    LibStoxConfig.BEACON_INITIAL_OWNER_NAME,
                    "address",
                    abi.encode(timelock),
                    ""
                )
            ),
            operation: Enum.Operation.Call
        });
        txs[1] = LibStoxMigrations.recordTx(bindBeaconInitialOwnerDeclaration());
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        (bytes memory value, uint256 registeredAt) = LibConfigRegistry.resolve(
            LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_INITIAL_OWNER_NAME, keccak256("address")
        );
        bytes memory expected = abi.encode(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        // forge-lint: disable-next-line(block-timestamp)
        if (keccak256(value) != keccak256(expected) || registeredAt != block.timestamp) {
            revert BeaconInitialOwnerBindingMismatch(value, registeredAt);
        }
        LibStoxMigrations.assertRecorded(bindBeaconInitialOwnerDeclaration());
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }
}
