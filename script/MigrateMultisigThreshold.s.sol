// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.18/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.18/src/lib/LibSafeTx.sol";

import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The Safe's `st0x.deploy` line is not at the record this one is
/// applied onto.
/// @param head The line's head.
error UnexpectedThresholdMigrationLine(bytes32 head);

/// @notice After the bundle, the record is not stamped with the block it
/// landed in.
/// @param expected The block timestamp.
/// @param actual The moment the registry answers.
error ThresholdRecordMismatch(uint256 expected, uint256 actual);

/// @notice After the bundle, the Safe's line does not end at this record.
/// @param head The line's head.
error ThresholdLineHeadMismatch(bytes32 head);

/// @notice This script's declaration: the Safe's record after the orchestrator
/// admin move.
/// @return The declaration.
function migrateMultisigThresholdDeclaration() pure returns (ScriptDeclaration memory) {
    return LibStoxMigrations.safeMigrationOnto(
        LibStoxMigrations.NAMESPACE,
        keccak256("script/MigrateMultisigThreshold.s.sol"),
        LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
        false
    );
}

/// @title MigrateMultisigThreshold
/// @notice Records the token-owner Safe's move to its policy threshold
/// (`LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD` of the pinned owners)
/// in the Safe's `st0x.deploy` line. The threshold changed on every chain
/// before the registry was in use, so the bundle is the record alone, stamped
/// with the block it lands in, onto the orchestrator admin move.
///
/// `run()` and `verify()` are `SafeBundleScript`'s.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = MigrateMultisigThreshold` per chain, after
/// `20261006-orchestrator-admin-to-timelock` has executed there.
contract MigrateMultisigThreshold is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return migrateMultisigThresholdDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x Safe: record the threshold migration";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/MigrateMultisigThreshold-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe already carries the policy this records, and its line is
    /// at the record this one is applied onto.
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        bytes32 head = LibStoxMigrations.head(chainSafe);
        if (head != migrateMultisigThresholdDeclaration().prerequisites[0].migration) {
            revert UnexpectedThresholdMigrationLine(head);
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The record, and nothing else.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        (address to, bytes memory data) = LibStoxMigrations.recordCall(
            migrateMultisigThresholdDeclaration(),
            address(safe()),
            LibTimelockInvariants.timelockForChainId(block.chainid)
        );
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The record is this bundle's and the Safe still carries the policy.
    function assertPostState() internal view override {
        address chainSafe = address(safe());
        uint256 record = LibStoxMigrations.applied(chainSafe, migrateMultisigThresholdDeclaration().id);
        // forge-lint: disable-next-line(block-timestamp)
        if (record != block.timestamp) {
            // forge-lint: disable-next-line(block-timestamp)
            revert ThresholdRecordMismatch(block.timestamp, record);
        }
        bytes32 head = LibStoxMigrations.head(chainSafe);
        if (head != migrateMultisigThresholdDeclaration().id) {
            revert ThresholdLineHeadMismatch(head);
        }
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }
}
