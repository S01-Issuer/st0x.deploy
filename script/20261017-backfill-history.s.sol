// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.21/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.21/src/lib/LibSafeTx.sol";

import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {deployGovernanceTimelockDeclaration} from "./20260729-deploy-governance-timelock.s.sol";
import {deployMissingTokensDeclaration} from "./20260807-deploy-missing-tokens.s.sol";
import {timelockRehearsalScheduleDeclaration} from "./20260813-timelock-rehearsal-schedule.s.sol";
import {timelockRehearsalCancelDeclaration} from "./20260813-timelock-rehearsal-cancel.s.sol";
import {executeTimelockOperationsDeclaration} from "./20260813-execute-timelock-operations.s.sol";
import {deployEuAuthoriserDeclaration} from "./20261006-deploy-eu-authoriser.s.sol";

/// @notice The Safe's line in the migration registry is not where this
/// script applies: either this bundle has already executed on the chain or
/// the line has not reached the orchestrator admin move.
/// @param head The line's head.
error UnexpectedMigrationLine(bytes32 head);

/// @notice After the bundle, a migration's record is not the one the bundle
/// wrote.
/// @param migration The migration.
/// @param expected The moment the bundle records.
/// @param actual The moment the registry answers.
error RecordMismatch(bytes32 migration, uint256 expected, uint256 actual);

/// @notice After the bundle, the Safe's line does not end at this script's
/// record.
/// @param head The line's head.
error LineHeadMismatch(bytes32 head);

/// @notice This script's declaration: the Safe's record after the records it
/// backfills.
/// @return The declaration.
function backfillHistoryDeclaration() pure returns (ScriptDeclaration memory) {
    return LibStoxMigrations.safeMigrationOnto(
        LibStoxMigrations.NAMESPACE,
        keccak256("script/20261017-backfill-history.s.sol"),
        deployEuAuthoriserDeclaration().id,
        false
    );
}

/// @notice The records this script's bundle writes, in line order: the
/// scripts that ran before they could record themselves, in the order they
/// ran, then this script's own.
/// @return The declarations.
function backfilledDeclarations() pure returns (ScriptDeclaration[] memory) {
    ScriptDeclaration[] memory declarations = new ScriptDeclaration[](7);
    declarations[0] = deployGovernanceTimelockDeclaration();
    declarations[1] = deployMissingTokensDeclaration();
    declarations[2] = timelockRehearsalScheduleDeclaration();
    declarations[3] = timelockRehearsalCancelDeclaration();
    declarations[4] = executeTimelockOperationsDeclaration();
    declarations[5] = deployEuAuthoriserDeclaration();
    declarations[6] = backfillHistoryDeclaration();
    return declarations;
}

/// @title BackfillHistory
/// @notice Authors the per-chain Safe Tx Builder bundle that records, in the
/// Safe's line of `rain-deploy`'s `MigrationRegistry`, the scripts that ran
/// before anything was recorded, then this script itself. One
/// `registry.applyMigration` per record, in one atomic MultiSend, each onto
/// the record before it.
///
/// The Safe's line starts at the orchestrator EMERGENCY grant, stamped with
/// the block it lands in, and the registry refuses a moment earlier than the
/// head it is applied onto. So these records carry the block this bundle
/// lands in, not the moments the scripts ran.
///
/// `run()` and `verify()` are `SafeBundleScript`'s.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261017-backfill-history` per chain. Refuses unless the Safe's
/// line is at the orchestrator admin move (`UnexpectedMigrationLine`).
contract BackfillHistory is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return backfillHistoryDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x registry: backfill the scripts that ran before records";
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Chain-suffixed, for the ACTIVE chain.
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261017-backfill-history-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The chain's token-owner Safe. `preflight` proves it in policy.
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe is what this repo pins and its line is where the first
    /// backfilled record applies.
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        bytes32 head = LibStoxMigrations.head(chainSafe);
        if (head != backfilledDeclarations()[0].prerequisites[0].migration) {
            revert UnexpectedMigrationLine(head);
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev One record per declaration, in line order.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address chainSafe = address(safe());
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        ScriptDeclaration[] memory declarations = backfilledDeclarations();
        SafeTx[] memory txs = new SafeTx[](declarations.length);
        for (uint256 i = 0; i < declarations.length; i++) {
            (address to, bytes memory data) = LibStoxMigrations.recordCall(declarations[i], chainSafe, timelock);
            txs[i] = SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
        }
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Every record carries this block, the line ends at this script's
    /// record, and the Safe still carries the token-owner policy.
    function assertPostState() internal view override {
        address chainSafe = address(safe());
        ScriptDeclaration[] memory declarations = backfilledDeclarations();
        for (uint256 i = 0; i < declarations.length; i++) {
            uint256 record = LibStoxMigrations.applied(chainSafe, declarations[i].id);
            // forge-lint: disable-next-line(block-timestamp)
            if (record != block.timestamp) {
                // forge-lint: disable-next-line(block-timestamp)
                revert RecordMismatch(declarations[i].id, block.timestamp, record);
            }
        }
        bytes32 head = LibStoxMigrations.head(chainSafe);
        if (head != backfillHistoryDeclaration().id) {
            revert LineHeadMismatch(head);
        }
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }
}
