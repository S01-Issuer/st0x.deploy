// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.29/src/abstract/SafeBundleScript.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.29/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.29/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.29/src/lib/LibConfigRegistryDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.29/src/lib/LibSafeTx.sol";

import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../src/lib/LibStoxConfig.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {migrateMultisigThresholdDeclaration} from "./20260619-migrate-multisig-threshold.s.sol";

/// @notice The Safe's line is not at the migration this bind applies onto.
/// @param head The line's head.
error BindGovernanceSafeUnexpectedLine(bytes32 head);

/// @notice The root authority has not approved the Safe to bind the
/// governance Safe.
/// @param safe The Safe.
error SafeNotGovernanceSafeDelegate(address safe);

/// @notice The governance Safe name is already bound to something other than
/// the Safe.
/// @param value The bound value.
/// @param valueTypeHash The bound value's type hash.
error GovernanceSafeBoundElsewhere(bytes value, bytes32 valueTypeHash);

/// @notice After the bundle, the governance Safe binding is not the Safe
/// bound in this block.
/// @param value The bound value.
/// @param registeredAt When it was bound.
error GovernanceSafeBindingMismatch(bytes value, uint256 registeredAt);

/// @notice After the bundle, this script's record is not this block's.
/// @param recordedAt The recorded moment.
error BindGovernanceSafeRecordMismatch(uint256 recordedAt);

/// @notice This script's declaration.
/// @return The declaration.
function bindGovernanceSafeDeclaration() pure returns (ScriptDeclaration memory) {
    return LibStoxMigrations.safeMigrationOnto(
        LibStoxMigrations.NAMESPACE,
        keccak256("script/20261103-bind-governance-safe.s.sol"),
        migrateMultisigThresholdDeclaration().id,
        false
    );
}

/// @title BindGovernanceSafe
/// @notice Authors the per-chain Safe bundle that binds
/// `LibStoxConfig.GOVERNANCE_SAFE_NAME` under the root authority to the chain's
/// token-owner Safe, as the root's approved delegate, and records it.
contract BindGovernanceSafe is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return bindGovernanceSafeDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x: bind the governance Safe";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261103-bind-governance-safe-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        LibConfigRegistry.checkCodeHash();
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);

        bytes32 head = LibStoxMigrations.head(chainSafe);
        if (head != bindGovernanceSafeDeclaration().prerequisites[0].migration) {
            revert BindGovernanceSafeUnexpectedLine(head);
        }
        IConfigRegistryV5 registry = IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        if (!registry.approvedV5(LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.GOVERNANCE_SAFE_NAME, chainSafe)) {
            revert SafeNotGovernanceSafeDelegate(chainSafe);
        }
        try registry.getV5(LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.GOVERNANCE_SAFE_NAME) returns (
            bytes memory value, uint256, bytes32 valueTypeHash
        ) {
            if (valueTypeHash != keccak256("address") || keccak256(value) != keccak256(abi.encode(chainSafe))) {
                revert GovernanceSafeBoundElsewhere(value, valueTypeHash);
            }
        } catch (bytes memory reason) {
            // Only an unbound name may proceed; any other revert is re-raised.
            if (bytes4(reason) != IConfigRegistryV5.NameNotRegistered.selector) {
                assembly ("memory-safe") {
                    revert(add(reason, 0x20), mload(reason))
                }
            }
        }
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address chainSafe = address(safe());
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({
            to: LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            value: 0,
            data: abi.encodeCall(
                IConfigRegistryV5.registerV5,
                (LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.GOVERNANCE_SAFE_NAME, "address", abi.encode(chainSafe), "")
            ),
            operation: Enum.Operation.Call
        });
        (address to, bytes memory data) =
            LibStoxMigrations.recordCall(bindGovernanceSafeDeclaration(), chainSafe, address(0));
        txs[1] = SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        address chainSafe = address(safe());
        (bytes memory value, uint256 registeredAt) = LibConfigRegistry.resolve(
            LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.GOVERNANCE_SAFE_NAME, keccak256("address")
        );
        // forge-lint: disable-next-line(block-timestamp)
        if (keccak256(value) != keccak256(abi.encode(chainSafe)) || registeredAt != block.timestamp) {
            revert GovernanceSafeBindingMismatch(value, registeredAt);
        }
        bytes32 id = bindGovernanceSafeDeclaration().id;
        uint256 recordedAt = LibStoxMigrations.applied(chainSafe, id);
        // forge-lint: disable-next-line(block-timestamp)
        if (recordedAt != block.timestamp) revert BindGovernanceSafeRecordMismatch(recordedAt);
        bytes32 head = LibStoxMigrations.head(chainSafe);
        if (head != id) revert BindGovernanceSafeUnexpectedLine(head);
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }
}
