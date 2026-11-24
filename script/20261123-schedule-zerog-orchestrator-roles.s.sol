// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.38/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";

import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibZerogOrchestratorRoles} from "../src/lib/LibZerogOrchestratorRoles.sol";

/// @notice The timelock does not hold `DEFAULT_ADMIN_ROLE` on the orchestrator, so the batch's orchestrator grants
/// would revert.
/// @param timelock The timelock.
error TimelockNotOrchestratorAdmin(address timelock);

/// @notice The batch is already registered on the timelock.
/// @param id The operation id.
error ZerogOrchestratorRolesAlreadyScheduled(bytes32 id);

/// @notice After the bundle the operation is not pending, or is ready inside its delay.
/// @param id The operation id.
error ZerogOrchestratorRolesNotPendingInsideDelay(bytes32 id);

/// @notice This script's declaration on the root line: right after the 0G token creation on every chain.
/// @return The declaration.
function scheduleZerogOrchestratorRolesDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES,
        onto: LibStoxMigrations.CREATE_ZEROG_TOKENS,
        history: false
    });
}

/// @title ScheduleZerogOrchestratorRoles
/// @notice Per-chain Safe bundle: on 0G, the Safe SCHEDULES the timelock batch `LibZerogOrchestratorRoles` builds,
/// which grants the service signer `MINT` and `BURN` and the Safe `EMERGENCY` on the orchestrator, and the
/// orchestrator `DEPOSIT` and `WITHDRAW` on the US authoriser, then writes its root-line record; elsewhere, where the
/// orchestrator already holds these roles, the record alone. The timelock holds every admin role these grants need,
/// so it is the only route.
///
/// The orchestrator's `DEFAULT_ADMIN_ROLE` is not enumerable, so the pre-flight can prove only that the timelock holds
/// it. 0G transaction 0x5d7b34d5f54c46ed036ec4959de1736f15af1b2b351f3dfc08f80bb1fcafc60c (block 50776661) deployed the
/// 0.1.30 set deployer and made its first `deploy(timelock)` in one Multicall3 call, so the timelock was the
/// instance's only initial admin and no one else could take the pinned address.
///
/// @dev Dispatch via `Actions → run-script` with `script = 20261123-schedule-zerog-orchestrator-roles` per chain.
/// After the delay anyone executes the batch: `20261123-execute-zerog-orchestrator-roles` `execute()`.
contract ScheduleZerogOrchestratorRoles is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return scheduleZerogOrchestratorRolesDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x RBAC: schedule the 0G orchestrator MINT, BURN, EMERGENCY, DEPOSIT and WITHDRAW grants";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261123-schedule-zerog-orchestrator-roles-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @notice The chain's governance timelock.
    /// @return The timelock.
    function timelock() internal view returns (address) {
        return LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    /// @notice Whether the active chain is 0G, the only chain the batch is for.
    /// @return True on 0G.
    function onZerog() internal view returns (bool) {
        return block.chainid == LibSafeInvariants.ZEROG_CHAIN_ID;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev On 0G: the orchestrator beacon set and instance are the audited 0.1.30 ones, the timelock administers the
    /// orchestrator and holds the US authoriser's map before these grants, none of the five grants is held and the
    /// batch is not registered.
    function preflight() internal view override {
        address chainSafe = address(safe());
        LibStoxMigrations.assertNext(scheduleZerogOrchestratorRolesDeclaration(), chainSafe);
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
        LibTimelockInvariants.assertTimelockState(timelock(), chainSafe);
        if (!onZerog()) return;

        LibOrchestratorInvariants.assertBeaconSet();
        LibOrchestratorInvariants.assertInstance();
        if (!IAccessControl(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE).hasRole(bytes32(0), timelock())) {
            revert TimelockNotOrchestratorAdmin(timelock());
        }
        LibAuthoriserInvariants.assertHeld(
            LibAuthoriserInvariants.activeChainAuthoriser(),
            LibAuthoriserInvariants.expectedGrantsWithoutOrchestrator(chainSafe, timelock())
        );
        LibZerogOrchestratorRoles.assertNoneGranted();

        bytes32 id = LibZerogOrchestratorRoles.operationId(timelock());
        if (TimelockController(payable(timelock())).isOperation(id)) revert ZerogOrchestratorRolesAlreadyScheduled(id);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev On 0G the schedule, then the record; elsewhere the record alone.
    function authorBundle() internal view override returns (SafeTx[] memory txs) {
        if (!onZerog()) {
            txs = new SafeTx[](1);
            txs[0] = LibStoxMigrations.recordTx(scheduleZerogOrchestratorRolesDeclaration());
            return txs;
        }
        txs = new SafeTx[](2);
        txs[0] = SafeTx({
            to: timelock(), value: 0, data: LibZerogOrchestratorRoles.scheduleCalldata(), operation: Enum.Operation.Call
        });
        txs[1] = LibStoxMigrations.recordTx(scheduleZerogOrchestratorRolesDeclaration());
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        if (onZerog()) {
            TimelockController controller = TimelockController(payable(timelock()));
            bytes32 id = LibZerogOrchestratorRoles.operationId(timelock());
            if (!controller.isOperationPending(id) || controller.isOperationReady(id)) {
                revert ZerogOrchestratorRolesNotPendingInsideDelay(id);
            }
        }
        LibStoxMigrations.assertRecorded(scheduleZerogOrchestratorRolesDeclaration());
    }

    /// @inheritdoc SafeBundleScript
    function assertReversible() internal override {
        if (!onZerog()) return;
        uint256 postBundle = vm.snapshotState();
        proveExecution();
        vm.revertToState(postBundle);
    }

    /// @notice After the delay, executes the batch as an address with no role and checks that the orchestrator and
    /// the US authoriser then hold every pair `LibIdealRoles` expects of them.
    function proveExecution() internal {
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = LibZerogOrchestratorRoles.batch();
        vm.prank(address(0xdead));
        TimelockController(payable(timelock()))
            .executeBatch(targets, values, payloads, bytes32(0), LibZerogOrchestratorRoles.SALT);

        LibZerogOrchestratorRoles.assertGranted();
        LibAuthoriserInvariants.assertExpectedGrants(
            LibAuthoriserInvariants.authoriserForChainId(block.chainid), address(safe()), timelock()
        );
        LibOrchestratorInvariants.assertExpectedGrants(address(safe()), timelock());
        console2.log("Execution proven: 0G orchestrator MINT, BURN, EMERGENCY, DEPOSIT and WITHDRAW granted");
    }
}
