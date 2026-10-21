// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.20/src/abstract/SafeBundleScript.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.20/src/interface/IMigrationRegistryV3.sol";
import {SafeTx} from "rain-deploy-0.1.20/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.20/src/lib/LibSafeFork.sol";

import {ST0xOrchestrator} from "../src/concrete/ST0xOrchestrator.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice This repo's line in the migration registry is not where this
/// script applies: it has recorded something, so either this bundle has
/// already executed on the chain or a migration this script does not know
/// about has.
/// @param head The line's head.
error UnexpectedMigrationLine(bytes32 head);

/// @notice The Safe is not approved to write this repo's line under
/// `LibStoxMigrations.WRITER`, so the record would revert.
/// @param safe The Safe.
error SafeNotApprovedWriter(address safe);

/// @notice The Safe already holds `EMERGENCY_ROLE` without the record this
/// script writes: it was granted outside a recorded migration.
error EmergencyAlreadyGranted();

/// @notice After the bundle, the migration's record is not the one the bundle
/// wrote.
/// @param migration The migration.
/// @param expected The moment the bundle records.
/// @param actual The moment the registry answers.
error RecordMismatch(bytes32 migration, uint256 expected, uint256 actual);

/// @notice After the bundle, this repo's line does not end at this script's
/// record.
/// @param head The line's head.
error LineHeadMismatch(bytes32 head);

/// @notice The n+1 revoke executed through the Safe and the Safe still
/// holds `EMERGENCY_ROLE`.
error EmergencyNotRevoked();

/// @title GrantOrchestratorEmergency
/// @notice Authors the per-chain Safe Tx Builder bundle that grants the
/// chain's token-owner Safe `EMERGENCY_ROLE` on the orchestrator, and starts
/// this repo's line in `rain-deploy`'s `MigrationRegistry`. Two calls, one
/// atomic MultiSend:
///
/// 1. `orchestrator.grantRole(EMERGENCY, safe)`.
/// 2. `registry.applyMigrationV3(WRITER, NAMESPACE, ORCHESTRATOR_EMERGENCY,
///    [genesis])`: the grant's record, stamped with the block it lands in,
///    written by the Safe as `LibStoxMigrations.WRITER`'s approved delegate.
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
/// the line has moved off genesis (`UnexpectedMigrationLine`), and until
/// `WRITER` has approved the Safe (`SafeNotApprovedWriter`).
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
    /// pins, this repo's line is at genesis and the Safe may write it, and the
    /// Safe does not yet hold `EMERGENCY_ROLE`.
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, chainSafe);
        LibOrchestratorInvariants.assertBeaconSet();

        bytes32 head = LibStoxMigrations.head();
        if (head != MIGRATION_HEAD_GENESIS) {
            revert UnexpectedMigrationLine(head);
        }
        if (!LibStoxMigrations.approved(chainSafe)) {
            revert SafeNotApprovedWriter(chainSafe);
        }
        if (ORCHESTRATOR.hasRole(ORCHESTRATOR.EMERGENCY_ROLE(), chainSafe)) {
            revert EmergencyAlreadyGranted();
        }
        LibOrchestratorInvariants.assertInstance(chainSafe);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The grant, then its record.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address chainSafe = address(safe());

        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({
            to: address(ORCHESTRATOR),
            value: 0,
            data: abi.encodeCall(IAccessControl.grantRole, (ORCHESTRATOR.EMERGENCY_ROLE(), chainSafe)),
            operation: Enum.Operation.Call
        });
        (address recordTo, bytes memory recordData) = LibStoxMigrations.applyMigrationCall(
            LibStoxMigrations.ORCHESTRATOR_EMERGENCY, LibStoxMigrations.onto(MIGRATION_HEAD_GENESIS)
        );
        txs[1] = SafeTx({to: recordTo, value: 0, data: recordData, operation: Enum.Operation.Call});
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The record is this bundle's, the orchestrator's roles are what it
    /// implies, and the Safe still carries the token-owner policy.
    function assertPostState() internal view override {
        address chainSafe = address(safe());
        // The registry stamps the block the record lands in, which on the
        // fork is this block: an equality with a known value, not a window.
        uint256 emergencyRecord = LibStoxMigrations.applied(LibStoxMigrations.ORCHESTRATOR_EMERGENCY);
        // forge-lint: disable-next-line(block-timestamp)
        if (emergencyRecord != block.timestamp) {
            // forge-lint: disable-next-line(block-timestamp)
            revert RecordMismatch(LibStoxMigrations.ORCHESTRATOR_EMERGENCY, block.timestamp, emergencyRecord);
        }
        bytes32 head = LibStoxMigrations.head();
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
