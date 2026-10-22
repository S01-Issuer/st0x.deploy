// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.21/src/abstract/SafeBundleScript.sol";
import {IConfigRegistryV3} from "rain-deploy-0.1.21/src/interface/IConfigRegistryV3.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.21/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.21/src/lib/LibConfigRegistryDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.21/src/lib/LibSafeTx.sol";

import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../src/lib/LibStoxConfig.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {migrateMultisigThresholdDeclaration} from "./20260619-migrate-multisig-threshold.s.sol";

/// @notice The Safe's line is not at the migration this bind applies onto.
/// @param head The line's head.
error BindBeaconOwnerUnexpectedLine(bytes32 head);

/// @notice The root authority has not approved the Safe to bind the beacon
/// owner.
/// @param safe The Safe.
error SafeNotBeaconOwnerDelegate(address safe);

/// @notice After the bundle, the beacon owner binding is not the timelock
/// bound in this block.
/// @param value The bound value.
/// @param registeredAt When it was bound.
error BeaconOwnerBindingMismatch(bytes value, uint256 registeredAt);

/// @notice After the bundle, this script's record is not this block's.
/// @param recordedAt The recorded moment.
error BindBeaconOwnerRecordMismatch(uint256 recordedAt);

/// @notice This script's declaration.
/// @return The declaration.
function bindBeaconOwnerDeclaration() pure returns (ScriptDeclaration memory) {
    return LibStoxMigrations.safeMigrationOnto(
        LibStoxMigrations.NAMESPACE,
        keccak256("script/20261022-bind-beacon-owner.s.sol"),
        migrateMultisigThresholdDeclaration().id,
        false
    );
}

/// @title BindBeaconOwner
/// @notice Authors the per-chain Safe bundle that binds
/// `LibStoxConfig.BEACON_OWNER` under the root authority to the chain's
/// governance timelock, as the root's approved delegate, and records it.
contract BindBeaconOwner is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return bindBeaconOwnerDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x: bind the beacon owner to the governance timelock";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261022-bind-beacon-owner-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        LibConfigRegistry.checkCodeHash();
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(LibTimelockInvariants.timelockForChainId(block.chainid), chainSafe);

        bytes32 head = LibStoxMigrations.head(chainSafe);
        if (head != bindBeaconOwnerDeclaration().prerequisites[0].migration) {
            revert BindBeaconOwnerUnexpectedLine(head);
        }
        if (!IConfigRegistryV3(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
                .approvedV3(LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_OWNER, chainSafe)) {
            revert SafeNotBeaconOwnerDelegate(chainSafe);
        }
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address chainSafe = address(safe());
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({
            to: LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            value: 0,
            data: abi.encodeCall(
                IConfigRegistryV3.registerV3,
                (LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_OWNER, abi.encode(timelock))
            ),
            operation: Enum.Operation.Call
        });
        (address to, bytes memory data) =
            LibStoxMigrations.recordCall(bindBeaconOwnerDeclaration(), chainSafe, timelock);
        txs[1] = SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        address chainSafe = address(safe());
        (bytes memory value, uint256 registeredAt) =
            LibConfigRegistry.resolve(LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_OWNER);
        // forge-lint: disable-next-line(block-timestamp)
        if (
            keccak256(value) != keccak256(abi.encode(LibTimelockInvariants.timelockForChainId(block.chainid)))
                || registeredAt != block.timestamp
        ) {
            revert BeaconOwnerBindingMismatch(value, registeredAt);
        }
        bytes32 id = bindBeaconOwnerDeclaration().id;
        uint256 recordedAt = LibStoxMigrations.applied(chainSafe, id);
        // forge-lint: disable-next-line(block-timestamp)
        if (recordedAt != block.timestamp) revert BindBeaconOwnerRecordMismatch(recordedAt);
        bytes32 head = LibStoxMigrations.head(chainSafe);
        if (head != id) revert BindBeaconOwnerUnexpectedLine(head);
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }
}
