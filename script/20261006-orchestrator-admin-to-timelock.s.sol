// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.21/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.21/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.21/src/lib/LibSafeFork.sol";

import {ST0xOrchestrator} from "../src/concrete/ST0xOrchestrator.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The Safe's line in the migration registry is not at the
/// orchestrator EMERGENCY grant, which this migration is applied onto:
/// the grant has not executed on this chain, this bundle already has, or
/// another Safe-recorded migration has landed after the grant. In the last
/// case this move can never apply onto the line as written and has to be
/// re-authored onto the new head.
/// @param head The line's head.
error UnexpectedMigrationLine(bytes32 head);

/// @notice After the bundle, the migration's record is not the one the
/// bundle wrote.
/// @param migration The migration.
/// @param expected The moment the bundle records.
/// @param actual The moment the registry answers.
error RecordMismatch(bytes32 migration, uint256 expected, uint256 actual);

/// @notice After the bundle, the Safe's line does not end at this script's
/// record.
/// @param head The line's head.
error LineHeadMismatch(bytes32 head);

/// @notice After the move, the Safe's direct grant on the orchestrator did
/// not revert for lacking `DEFAULT_ADMIN_ROLE`.
/// @param success Whether the grant went through.
/// @param reason The revert data, when it did not.
error DirectGrantNotRefused(bool success, bytes reason);

/// @notice The timelock's minimum delay is not the pinned one.
/// @param expected The pinned delay.
/// @param actual The timelock's.
error TimelockMinDelayUnexpected(uint256 expected, uint256 actual);

/// @notice The timelock accepted a schedule with less than its minimum
/// delay.
error ShortDelayAccepted();

/// @notice The scheduled grant is not pending, or is already ready, inside
/// the delay.
/// @param operationId The timelock operation.
error GrantReadyInsideDelay(bytes32 operationId);

/// @notice The scheduled grant did not execute after the delay.
/// @param operationId The timelock operation.
error ScheduledGrantNotExecuted(bytes32 operationId);

/// @notice This script's declaration: the Safe's record after the
/// orchestrator EMERGENCY grant.
/// @return The declaration.
function orchestratorAdminToTimelockDeclaration() pure returns (ScriptDeclaration memory) {
    return LibStoxMigrations.safeMigrationOnto(
        LibStoxMigrations.NAMESPACE,
        LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
        LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
        false
    );
}

/// @title OrchestratorAdminToTimelock
/// @notice Authors the per-chain Safe Tx Builder bundle that moves the
/// orchestrator's `DEFAULT_ADMIN_ROLE` from the chain's token-owner Safe to
/// the chain's governance timelock. Three calls, one atomic MultiSend:
///
/// 1. `orchestrator.grantRole(DEFAULT_ADMIN, timelock)`.
/// 2. `orchestrator.renounceRole(DEFAULT_ADMIN, safe)`.
/// 3. `registry.applyMigrationV3(safe, ORCHESTRATOR_ADMIN_TO_TIMELOCK,
///    [ORCHESTRATOR_EMERGENCY])`.
///
/// `DEFAULT_ADMIN_ROLE` administers `MINT_ROLE`, `BURN_ROLE` and
/// `EMERGENCY_ROLE` on the audited 0.1.30 orchestrator, so after this every
/// grant and revoke of those roles is a timelock operation: Safe schedules,
/// 48h, anyone executes. The roles themselves are untouched, so minting,
/// burning and emergency recovery are not delayed. A holder can still
/// `renounceRole` itself immediately.
///
/// The record is applied onto the EMERGENCY grant's, so the registry
/// refuses it on a chain where that grant has not executed: the Safe must be
/// granted `EMERGENCY_ROLE` while it can still do so directly.
///
/// **Before signing: cancel any timelock operation already scheduled against
/// the orchestrator.** `schedule` does not run the inner call, so a
/// `grantRole`/`revokeRole` on the orchestrator can sit pending or ready
/// today while it would revert if executed. Once the timelock holds
/// `DEFAULT_ADMIN_ROLE` the same operation becomes a real role change, and
/// execution is open to anyone with no expiry: a leftover
/// `grantRole(DEFAULT_ADMIN, x)` hands admin out with no further delay, and a
/// `revokeRole(DEFAULT_ADMIN, timelock)` leaves the orchestrator without an
/// admin. Read them on the rain-org-health dashboard's Role changes tab,
/// https://rainlanguage.github.io/rain-org-health/deployments.html, which
/// shows per network the governance timelock's pending operations, read live
/// from this repo's RBAC subgraph (`st0x-rbac-<network>`, version `prod`).
/// Check the network's index reads as current, then cancel exactly the
/// pending operations with a call targeting the orchestrator. The same read
/// against the subgraph:
/// `{ timelockOperations(where: {timelock: "<timelock>", status: PENDING, targets_contains: ["<orchestrator>"]}) { operationId readyAt calls { target data } } }`.
/// `cancel` reverts on anything not pending, so including a cancelled or
/// done id reverts the whole Safe transaction.
///
/// **Before signing: confirm the Safe is the only `DEFAULT_ADMIN_ROLE`
/// holder.** Membership is not enumerable on chain, so the invariants check
/// only the Safe and the timelock. On the same tab, the orchestrator's
/// current `DEFAULT_ADMIN_ROLE` holders must be exactly the Safe. The same
/// read against the subgraph:
/// `{ roleHolders(where: {role_: {contract: "<orchestrator>", role: "0x0000000000000000000000000000000000000000000000000000000000000000"}, held: true}) { account } }`.
/// A third holder would keep immediate admin power after this move.
///
/// **Execute on every chain before any upgrade of the orchestrator, receipt
/// vault or receipt beacon is scheduled.** The pre-flight pins the 0.1.30
/// orchestrator implementation and the vault logic it was built against
/// (`vaultLogicIsExpected`), so after any such upgrade this script refuses
/// there; for the per-role-admin orchestrator upgrade the Safe, still
/// `DEFAULT_ADMIN_ROLE`, can then call `migrate(safe)` directly (see
/// `docs/TIMELOCK.md`).
///
/// `run()` and `verify()` are `SafeBundleScript`'s: `run()` executes the
/// bundle through the Safe on the fork, requires the post-state, proves the
/// Safe governs through the timelock afterwards (`assertReversible`) and
/// writes the artifact; `verify(path)` holds a downloaded artifact to the
/// bundle re-derived from live state.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261006-orchestrator-admin-to-timelock` per chain, only after
/// `20261006-grant-orchestrator-emergency` has executed there.
contract OrchestratorAdminToTimelock is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return orchestratorAdminToTimelockDeclaration();
    }

    /// @notice The orchestrator instance, typed for its role-id getters.
    ST0xOrchestrator internal constant ORCHESTRATOR =
        ST0xOrchestrator(payable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE));

    /// @notice Salt for the post-move governance proof's timelock operation.
    /// Fork-only; never scheduled on chain.
    bytes32 internal constant PROOF_SALT = keccak256("st0x.orchestrator-admin-to-timelock.proof");

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x orchestrator: move DEFAULT_ADMIN_ROLE to the governance timelock";
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Chain-suffixed, for the ACTIVE chain.
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261006-orchestrator-admin-to-timelock-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The chain's token-owner Safe. `preflight` proves it in policy.
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @notice The chain's governance timelock. `preflight` proves its state.
    /// @return The timelock.
    function timelock() internal view returns (address) {
        return LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe, the timelock and the orchestrator are what this repo
    /// pins, the Safe's registry line is at the EMERGENCY grant, and the
    /// orchestrator carries what that record implies: Safe EMERGENCY.
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock(), chainSafe);
        LibOrchestratorInvariants.assertBeaconSet();

        bytes32 head = LibStoxMigrations.head(chainSafe);
        if (head != orchestratorAdminToTimelockDeclaration().prerequisites[0].migration) {
            revert UnexpectedMigrationLine(head);
        }
        LibOrchestratorInvariants.assertInstance(chainSafe);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The grant, the renounce, then the record.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address chainSafe = address(safe());
        SafeTx[] memory txs = new SafeTx[](3);
        txs[0] = SafeTx({
            to: address(ORCHESTRATOR),
            value: 0,
            data: abi.encodeCall(IAccessControl.grantRole, (bytes32(0), timelock())),
            operation: Enum.Operation.Call
        });
        txs[1] = SafeTx({
            to: address(ORCHESTRATOR),
            value: 0,
            data: abi.encodeCall(IAccessControl.renounceRole, (bytes32(0), chainSafe)),
            operation: Enum.Operation.Call
        });
        (address recordTo, bytes memory recordData) =
            LibStoxMigrations.recordCall(orchestratorAdminToTimelockDeclaration(), chainSafe, timelock());
        txs[2] = SafeTx({to: recordTo, value: 0, data: recordData, operation: Enum.Operation.Call});
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The record is this bundle's, the orchestrator's roles are what it
    /// implies, and the Safe still carries the token-owner policy.
    function assertPostState() internal view override {
        address chainSafe = address(safe());
        // The registry stamps the block the record lands in, which on the
        // fork is this block: an equality with a known value, not a window.
        uint256 record = LibStoxMigrations.applied(chainSafe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK);
        // forge-lint: disable-next-line(block-timestamp)
        if (record != block.timestamp) {
            // forge-lint: disable-next-line(block-timestamp)
            revert RecordMismatch(LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK, block.timestamp, record);
        }
        bytes32 head = LibStoxMigrations.head(chainSafe);
        if (head != orchestratorAdminToTimelockDeclaration().id) {
            revert LineHeadMismatch(head);
        }
        LibOrchestratorInvariants.assertInstance(chainSafe);
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The move's governance proof: the Safe's direct grant now reverts,
    /// and the same grant scheduled through the timelock by the Safe's real
    /// threshold-gated exec is not ready inside the 48h window and executes
    /// after it. The Safe keeps every admin power, 48h later, including the
    /// power to move admin back.
    ///
    /// The operation re-grants `EMERGENCY_ROLE` to the Safe, which already
    /// holds it, so it changes nothing; it still only succeeds if the
    /// timelock administers the role, because `grantRole` checks the
    /// caller's admin role before it checks membership.
    function assertReversible() internal override {
        // The proof warps past the delay and executes a timelock operation.
        // `run()` writes the artifact from the fork this returns to, so it
        // returns to the post-bundle state rather than 48h later.
        uint256 postBundle = vm.snapshotState();
        proveGovernance();
        vm.revertToState(postBundle);
    }

    /// @notice The governance proof `assertReversible` runs: the Safe's direct
    /// grant refused, then schedule → 48h → execute through the timelock.
    function proveGovernance() internal {
        Safe chainSafe = safe();
        address controllerAddress = timelock();
        bytes memory grant =
            abi.encodeCall(IAccessControl.grantRole, (ORCHESTRATOR.EMERGENCY_ROLE(), address(chainSafe)));

        vm.prank(address(chainSafe));
        // slither-disable-next-line low-level-calls
        (bool directOk, bytes memory directRet) = address(ORCHESTRATOR).call(grant);
        if (
            directOk
                || keccak256(directRet)
                    != keccak256(
                        abi.encodeWithSelector(
                            IAccessControl.AccessControlUnauthorizedAccount.selector, address(chainSafe), bytes32(0)
                        )
                    )
        ) {
            revert DirectGrantNotRefused(directOk, directRet);
        }

        TimelockController controller = TimelockController(payable(controllerAddress));
        // The delay is the timelock's, not the script's: scheduling with less
        // than the pinned minimum must revert.
        uint256 minDelay = controller.getMinDelay();
        if (minDelay != LibTimelockInvariants.TIMELOCK_MIN_DELAY) {
            revert TimelockMinDelayUnexpected(LibTimelockInvariants.TIMELOCK_MIN_DELAY, minDelay);
        }
        vm.prank(address(chainSafe));
        // slither-disable-next-line low-level-calls
        (bool shortOk,) = controllerAddress.call(
            abi.encodeCall(
                TimelockController.schedule,
                (address(ORCHESTRATOR), 0, grant, bytes32(0), PROOF_SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY - 1)
            )
        );
        if (shortOk) {
            revert ShortDelayAccepted();
        }
        bytes32 id = controller.hashOperation(address(ORCHESTRATOR), 0, grant, bytes32(0), PROOF_SALT);
        LibSafeFork.simulateNPlus1(
            vm,
            chainSafe,
            controllerAddress,
            abi.encodeCall(
                TimelockController.schedule,
                (address(ORCHESTRATOR), 0, grant, bytes32(0), PROOF_SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
            )
        );
        if (!controller.isOperationPending(id) || controller.isOperationReady(id)) {
            revert GrantReadyInsideDelay(id);
        }

        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        // Execution is open to anyone; executing from an address with no
        // role proves the operation does not depend on the Safe.
        vm.prank(address(0xdead));
        controller.execute(address(ORCHESTRATOR), 0, grant, bytes32(0), PROOF_SALT);
        if (!controller.isOperationDone(id)) {
            revert ScheduledGrantNotExecuted(id);
        }
        console2.log("Governance proven: direct grant refused; schedule -> 48h -> execute through the timelock");
    }
}
