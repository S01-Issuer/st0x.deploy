// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibServiceSignerRevoke} from "../src/lib/LibServiceSignerRevoke.sol";

/// @notice The timelock does not hold the admin role of `role`.
/// @param timelock The timelock.
/// @param adminRole The admin role.
error TimelockLacksAdminRole(address timelock, bytes32 adminRole);

/// @notice The service signer does not hold `role`, so the revoke has nothing to do.
/// @param role The role.
error ServiceSignerLacksRole(bytes32 role);

/// @notice The revoke batch is already registered on the timelock.
/// @param id The operation id.
error RevokeAlreadyScheduled(bytes32 id);

/// @notice After the bundle the operation is not pending, or is ready inside its delay.
/// @param id The operation id.
error RevokeNotPendingInsideDelay(bytes32 id);

/// @notice This script's declaration: the Safe's record, after the naming execute.
/// @return The declaration.
function scheduleRevokeServiceSignerDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.SCHEDULE_REVOKE_SERVICE_SIGNER,
        onto: LibStoxMigrations.EXECUTE_UNDERLYING_NAMING,
        history: false
    });
}

/// @title ScheduleRevokeServiceSignerDepositWithdraw
/// @notice Authors the per-chain Safe bundle that SCHEDULES the timelock batch
/// revoking `DEPOSIT` and `WITHDRAW` from the service signer on the chain's
/// authoriser, then writes the Safe's root-line record. The timelock holds
/// `DEPOSIT_ADMIN` and `WITHDRAW_ADMIN`, so it is the only route.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261109-schedule-revoke-service-signer-deposit-withdraw` per chain.
contract ScheduleRevokeServiceSignerDepositWithdraw is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return scheduleRevokeServiceSignerDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x RBAC: schedule revoking DEPOSIT and WITHDRAW from the service signer";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat(
            "out/20261109-schedule-revoke-service-signer-deposit-withdraw-", vm.toString(block.chainid), ".json"
        );
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

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock(), chainSafe);
        LibStoxMigrations.assertNext(scheduleRevokeServiceSignerDeclaration(), chainSafe);
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        IAccessControl access = IAccessControl(authoriser);
        address signer = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

        if (!access.hasRole(keccak256("DEPOSIT_ADMIN"), timelock())) {
            revert TimelockLacksAdminRole(timelock(), keccak256("DEPOSIT_ADMIN"));
        }
        if (!access.hasRole(keccak256("WITHDRAW_ADMIN"), timelock())) {
            revert TimelockLacksAdminRole(timelock(), keccak256("WITHDRAW_ADMIN"));
        }
        if (!access.hasRole(keccak256("DEPOSIT"), signer)) revert ServiceSignerLacksRole(keccak256("DEPOSIT"));
        if (!access.hasRole(keccak256("WITHDRAW"), signer)) revert ServiceSignerLacksRole(keccak256("WITHDRAW"));

        bytes32 id = LibServiceSignerRevoke.operationId(timelock(), block.chainid);
        if (TimelockController(payable(timelock())).isOperation(id)) revert RevokeAlreadyScheduled(id);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The schedule, then the record.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({
            to: timelock(),
            value: 0,
            data: LibServiceSignerRevoke.scheduleCalldata(block.chainid),
            operation: Enum.Operation.Call
        });
        txs[1] = LibStoxMigrations.recordTx(scheduleRevokeServiceSignerDeclaration());
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        TimelockController controller = TimelockController(payable(timelock()));
        bytes32 id = LibServiceSignerRevoke.operationId(timelock(), block.chainid);
        if (!controller.isOperationPending(id) || controller.isOperationReady(id)) {
            revert RevokeNotPendingInsideDelay(id);
        }
        LibStoxMigrations.assertRecorded(scheduleRevokeServiceSignerDeclaration());
    }

    /// @inheritdoc SafeBundleScript
    function assertReversible() internal override {
        uint256 postBundle = vm.snapshotState();
        proveExecution();
        vm.revertToState(postBundle);
    }

    /// @notice After the delay, executes the batch as an address with no role
    /// and checks the authoriser's grants.
    function proveExecution() internal {
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibServiceSignerRevoke.batch(block.chainid);
        vm.prank(address(0xdead));
        TimelockController(payable(timelock()))
            .executeBatch(targets, values, payloads, bytes32(0), LibServiceSignerRevoke.SALT);

        address authoriser = LibAuthoriserInvariants.authoriserForChainId(block.chainid);
        LibServiceSignerRevoke.assertRevoked(authoriser);
        LibAuthoriserInvariants.assertExpectedGrants(authoriser, address(safe()), timelock());
        console2.log("Execution proven: service signer DEPOSIT and WITHDRAW revoked by a roleless executor");
    }
}
