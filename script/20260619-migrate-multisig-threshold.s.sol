// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.22/src/interface/IMigrationRegistryV3.sol";
import {SafeBundleScript} from "rain-deploy-0.1.22/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.22/src/lib/LibSafeTx.sol";
import {LibSafe} from "rain-deploy-0.1.22/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.22/src/lib/LibSafeFork.sol";

import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";

/// @notice This script's declaration: the line's first record.
/// @return The declaration.
function migrateMultisigThresholdDeclaration() pure returns (ScriptDeclaration memory) {
    return LibStoxMigrations.migrationOnto(
        keccak256("script/20260619-migrate-multisig-threshold.s.sol"), MIGRATION_HEAD_GENESIS
    );
}

/// @title MigrateMultisigThreshold
/// @notice Authors the per-chain Safe Tx Builder bundle that raises the
/// chain's token-owner Safe to its pinned threshold
/// (`STOX_TOKEN_OWNER_SAFE_THRESHOLD`) over the pinned owner set and records
/// it, in one atomic MultiSend:
///
/// 1. `safe.changeThreshold(STOX_TOKEN_OWNER_SAFE_THRESHOLD)`, only if the
///    Safe is not at it yet.
/// 2. `registry.applyMigrationV3(WRITER, NAMESPACE, <this script>,
///    [genesis])`, written by the Safe as `LibStoxMigrations.WRITER`'s
///    approved delegate.
///
/// `run()` and `verify()` are `SafeBundleScript`'s; `run()` also proves the
/// Safe can move back to its creation threshold under the new one.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20260619-migrate-multisig-threshold` per chain.
contract MigrateMultisigThreshold is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return migrateMultisigThresholdDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x Safe threshold to the pinned policy";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20260619-migrate-multisig-threshold-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe is locked down with the pinned owners, and this is the
    /// line's next record, which the Safe may write.
    function preflight() internal view override {
        Safe chainSafe = safe();
        LibSafe.assertLockedDown(chainSafe);
        LibSafe.assertOwnersAsSet(chainSafe, LibSafeInvariants.expectedOwners());
        LibStoxMigrations.assertNext(migrateMultisigThresholdDeclaration(), address(chainSafe));
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The threshold change if the Safe is not at the pin, then the
    /// record.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        Safe chainSafe = safe();
        SafeTx memory record = LibStoxMigrations.recordTx(migrateMultisigThresholdDeclaration());
        if (chainSafe.getThreshold() == LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD) {
            SafeTx[] memory recordOnly = new SafeTx[](1);
            recordOnly[0] = record;
            return recordOnly;
        }
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({
            to: address(chainSafe),
            value: 0,
            data: abi.encodeCall(OwnerManager.changeThreshold, (LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD)),
            operation: Enum.Operation.Call
        });
        txs[1] = record;
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The record is this bundle's and the Safe carries the full
    /// token-owner policy, threshold included.
    function assertPostState() internal view override {
        LibStoxMigrations.assertRecorded(migrateMultisigThresholdDeclaration());
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe can return to its creation threshold under the pinned
    /// one. The fork returns to the post-bundle state.
    function assertReversible() internal override {
        uint256 postBundle = vm.snapshotState();
        LibSafeFork.simulateThresholdNPlus1(vm, safe(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_CREATION_THRESHOLD);
        vm.revertToState(postBundle);
    }
}
