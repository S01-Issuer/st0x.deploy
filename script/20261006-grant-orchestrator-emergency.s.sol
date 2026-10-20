// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.19/src/abstract/SafeBundleScript.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.19/src/interface/IMigrationRegistryV3.sol";
import {SafeTx} from "rain-deploy-0.1.19/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.19/src/lib/LibSafeFork.sol";

import {ST0xOrchestrator} from "../src/concrete/ST0xOrchestrator.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The Safe's line in the migration registry is not where this
/// script applies: it has recorded something, so either this bundle has
/// already executed on the chain or a migration this script does not know
/// about has.
/// @param head The line's head.
error UnexpectedMigrationLine(bytes32 head);

/// @notice The Safe already holds `EMERGENCY_ROLE` without the record this
/// script writes: it was granted outside a recorded migration.
error EmergencyAlreadyGranted();

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

/// @notice The n+1 revoke executed through the Safe and the Safe still
/// holds `EMERGENCY_ROLE`.
error EmergencyNotRevoked();

/// @title GrantOrchestratorEmergency
/// @notice Authors the per-chain Safe Tx Builder bundle that grants the
/// chain's token-owner Safe `EMERGENCY_ROLE` on the orchestrator, and starts
/// the Safe's line in `rain-deploy`'s `MigrationRegistry`. Three calls, one
/// atomic MultiSend:
///
/// 1. `orchestrator.grantRole(EMERGENCY, safe)`.
/// 2. `registry.applyMigrationHistoryV3(safe, GOVERNANCE_TIMELOCK, executedAt,
///    [genesis])`: the governance-timelock migration ran before anything
///    was recorded, so it is recorded with the moment it executed on this
///    chain (`LibStoxMigrations.governanceTimelockExecution`). Recording it
///    first keeps the line in the order the migrations ran; once anything
///    later is recorded, the registry refuses an earlier moment.
/// 3. `registry.applyMigrationV3(safe, ORCHESTRATOR_EMERGENCY,
///    [GOVERNANCE_TIMELOCK])`: the grant's own record, stamped with the
///    block it lands in.
///
/// `EMERGENCY_ROLE` is administered by `DEFAULT_ADMIN_ROLE`, which the Safe
/// holds, so the grant is immediate. The admin move to the timelock is
/// `20261006-orchestrator-admin-to-timelock`, which waits on this record.
///
/// `LibOrchestratorInvariants.assertInstance` reads the record: once it is
/// recorded, the Safe must hold `EMERGENCY_ROLE`.
///
/// `run()` and `verify()` are `SafeBundleScript`'s: `run()` executes the
/// bundle through the Safe on the fork, requires the post-state, proves the
/// Safe can revoke the role again under its live threshold and writes the
/// artifact; `verify(path)` holds a downloaded artifact to the bundle
/// re-derived from live state.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261006-grant-orchestrator-emergency` per chain. Refuses once
/// the Safe's line has moved off genesis (`UnexpectedMigrationLine`).
contract GrantOrchestratorEmergency is SafeBundleScript {
    /// @notice The orchestrator instance, typed for its role-id getters.
    ST0xOrchestrator internal constant ORCHESTRATOR =
        ST0xOrchestrator(payable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE));

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x orchestrator: grant EMERGENCY_ROLE to the token-owner Safe";
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Chain-suffixed, for the ACTIVE chain.
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261006-grant-orchestrator-emergency-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The chain's token-owner Safe. `preflight` proves it in policy.
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe, the timelock and the orchestrator are what this repo
    /// pins, the Safe's registry line is at genesis, and the Safe does not yet
    /// hold `EMERGENCY_ROLE`.
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, chainSafe);
        LibOrchestratorInvariants.assertBeaconSet();

        bytes32 head = LibStoxMigrations.head(chainSafe);
        if (head != MIGRATION_HEAD_GENESIS) {
            revert UnexpectedMigrationLine(head);
        }
        if (ORCHESTRATOR.hasRole(ORCHESTRATOR.EMERGENCY_ROLE(), chainSafe)) {
            revert EmergencyAlreadyGranted();
        }
        LibOrchestratorInvariants.assertInstance(chainSafe);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The grant, then the two records.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address chainSafe = address(safe());
        (uint256 executedAt,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);

        SafeTx[] memory txs = new SafeTx[](3);
        txs[0] = SafeTx({
            to: address(ORCHESTRATOR),
            value: 0,
            data: abi.encodeCall(IAccessControl.grantRole, (ORCHESTRATOR.EMERGENCY_ROLE(), chainSafe)),
            operation: Enum.Operation.Call
        });
        (address historyTo, bytes memory historyData) = LibStoxMigrations.applyMigrationHistoryCall(
            chainSafe,
            LibStoxMigrations.GOVERNANCE_TIMELOCK,
            executedAt,
            LibStoxMigrations.onto(chainSafe, MIGRATION_HEAD_GENESIS)
        );
        txs[1] = SafeTx({to: historyTo, value: 0, data: historyData, operation: Enum.Operation.Call});
        (address recordTo, bytes memory recordData) = LibStoxMigrations.applyMigrationCall(
            chainSafe,
            LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
            LibStoxMigrations.onto(chainSafe, LibStoxMigrations.GOVERNANCE_TIMELOCK)
        );
        txs[2] = SafeTx({to: recordTo, value: 0, data: recordData, operation: Enum.Operation.Call});
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The records are exactly the two this bundle writes, the
    /// orchestrator's roles are what they imply, and the Safe still carries the
    /// token-owner policy.
    function assertPostState() internal view override {
        address chainSafe = address(safe());
        (uint256 executedAt,) = LibStoxMigrations.governanceTimelockExecution(block.chainid);
        uint256 timelockRecord = LibStoxMigrations.applied(chainSafe, LibStoxMigrations.GOVERNANCE_TIMELOCK);
        if (timelockRecord != executedAt) {
            revert RecordMismatch(LibStoxMigrations.GOVERNANCE_TIMELOCK, executedAt, timelockRecord);
        }
        // The registry stamps the block the record lands in, which on the
        // fork is this block: an equality with a known value, not a window.
        uint256 emergencyRecord = LibStoxMigrations.applied(chainSafe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY);
        // forge-lint: disable-next-line(block-timestamp)
        if (emergencyRecord != block.timestamp) {
            // forge-lint: disable-next-line(block-timestamp)
            revert RecordMismatch(LibStoxMigrations.ORCHESTRATOR_EMERGENCY, block.timestamp, emergencyRecord);
        }
        bytes32 head = LibStoxMigrations.head(chainSafe);
        if (head != LibStoxMigrations.ORCHESTRATOR_EMERGENCY) {
            revert LineHeadMismatch(head);
        }
        LibOrchestratorInvariants.assertInstance(chainSafe);
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe can still revoke the role under the live threshold. The
    /// registry record is permanent, so a real revoke must ship with its own
    /// recorded migration (and a matching branch in
    /// `LibOrchestratorInvariants.assertInstance`), or every later
    /// `assertInstance` caller reverts. Re-grants so the fork ends in the
    /// post-bundle state.
    function assertReversible() internal override {
        Safe chainSafe = safe();
        bytes32 emergencyRole = ORCHESTRATOR.EMERGENCY_ROLE();
        LibSafeFork.simulateNPlus1(
            vm,
            chainSafe,
            address(ORCHESTRATOR),
            abi.encodeCall(IAccessControl.revokeRole, (emergencyRole, address(chainSafe)))
        );
        if (ORCHESTRATOR.hasRole(emergencyRole, address(chainSafe))) {
            revert EmergencyNotRevoked();
        }
        LibSafeFork.simulateCall(
            vm,
            chainSafe,
            address(ORCHESTRATOR),
            abi.encodeCall(IAccessControl.grantRole, (emergencyRole, address(chainSafe)))
        );
    }
}
