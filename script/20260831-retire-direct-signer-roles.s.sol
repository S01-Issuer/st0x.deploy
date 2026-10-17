// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.18/src/abstract/SafeBundleScript.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.18/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.18/src/lib/LibMigrationRegistry.sol";
import {SafeTx} from "rain-deploy-0.1.18/src/lib/LibSafeTx.sol";

import {IStoxScript, MigrationPrerequisite, MigrationWriter, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibRbacMigration} from "../src/lib/LibRbacMigration.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The orchestrator mint/burn path is not fully enabled, so retiring
/// the signer's direct roles would leave no working mint/burn path.
/// @param holder The principal missing a role.
/// @param role The role it must hold.
error OrchestratorPathNotEnabled(address holder, bytes32 role);

/// @notice The timelock does not hold an `_ADMIN` the revokes need.
/// @param adminRole The missing `_ADMIN` role.
error TimelockMissingRoleAdminForRetire(bytes32 adminRole);

/// @notice The signer no longer holds a direct role this retires.
/// @param role The role it does not hold.
error DirectSignerRoleAlreadyRetired(bytes32 role);

/// @notice The timelock's `st0x.rbac` line is not at the record this one is
/// applied onto.
/// @param head The line's head.
error UnexpectedRetireMigrationLine(bytes32 head);

/// @notice The retirement operation is already registered on the timelock.
/// @param operationId The operation.
error RetirementAlreadyScheduled(bytes32 operationId);

/// @notice After the bundle, the operation is not pending, or is ready inside
/// the delay.
/// @param operationId The operation.
error RetirementNotPendingInsideDelay(bytes32 operationId);

/// @notice After executing the operation, the state is not what it records.
/// @param check The check that failed.
error RetirementPostStateMismatch(string check);

/// @notice This script's declaration: the timelock's first record in the RBAC
/// namespace, written by the scheduled batch itself.
/// @return declared The declaration.
function retireDirectSignerRolesDeclaration() pure returns (ScriptDeclaration memory declared) {
    MigrationPrerequisite[] memory prerequisites = new MigrationPrerequisite[](1);
    prerequisites[0] = MigrationPrerequisite({
        writer: MigrationWriter.Timelock,
        namespace: LibRbacMigration.STOX_RBAC_NAMESPACE,
        migration: MIGRATION_HEAD_GENESIS
    });
    declared = ScriptDeclaration({
        migration: true,
        namespace: LibRbacMigration.STOX_RBAC_NAMESPACE,
        id: LibRbacMigration.SERVICE_SIGNER_DIRECT_ROLES_RETIRED,
        writer: MigrationWriter.Timelock,
        prerequisites: prerequisites,
        history: false
    });
}

/// @title RetireDirectSignerRoles
/// @notice Authors the per-chain Safe bundle that schedules, on the governance
/// timelock, one batch retiring the service signer's direct `DEPOSIT` and
/// `WITHDRAW` on the production authoriser, leaving the orchestrator as the
/// only mint/burn path the signer drives. The timelock holds the vault
/// `_ADMIN`s, so the revokes are its calls; the batch's last call records the
/// retirement under the timelock, so the record lands atomically with them.
///
/// After the 48h delay anyone may execute the batch;
/// `20260813-execute-timelock-operations` does that from CI.
///
/// Untouched: the signer's `CERTIFY` and the Safe's own direct action roles.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20260831-retire-direct-signer-roles` per chain.
contract RetireDirectSignerRoles is SafeBundleScript, IStoxScript {
    /// @notice The service signer whose direct vault access retires.
    address internal constant SERVICE_SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

    /// @notice The salt the scheduled batch is registered under.
    bytes32 internal constant RETIRE_SALT = keccak256("st0x.rbac.service-signer.direct-roles-retired");

    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return retireDirectSignerRolesDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x retire: schedule the service signer's direct vault role revokes";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20260831-retire-direct-signer-roles-", vm.toString(block.chainid), ".json");
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

    /// @notice The chain's production authoriser.
    /// @return The authoriser.
    function authoriser() internal view returns (address) {
        return LibAuthoriserInvariants.authoriserForChainId(block.chainid);
    }

    /// @notice The scheduled batch: both revokes, then the record.
    /// @return targets Each call's target.
    /// @return values Each call's value, all zero.
    /// @return payloads Each call's calldata.
    function batch()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        targets = new address[](3);
        values = new uint256[](3);
        payloads = new bytes[](3);
        targets[0] = authoriser();
        payloads[0] = abi.encodeCall(IAccessControl.revokeRole, (keccak256("DEPOSIT"), SERVICE_SIGNER));
        targets[1] = authoriser();
        payloads[1] = abi.encodeCall(IAccessControl.revokeRole, (keccak256("WITHDRAW"), SERVICE_SIGNER));
        (targets[2], payloads[2]) =
            LibStoxMigrations.recordCall(retireDirectSignerRolesDeclaration(), address(safe()), timelock());
    }

    /// @notice The batch's timelock operation id.
    /// @return The id.
    function operationId() internal view returns (bytes32) {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch();
        return
            TimelockController(payable(timelock()))
                .hashOperationBatch(targets, values, payloads, bytes32(0), RETIRE_SALT);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The orchestrator path is fully enabled, the timelock can revoke,
    /// the signer still holds both roles, the timelock's RBAC line is at
    /// genesis and the batch is not already scheduled.
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock(), chainSafe);
        IAccessControl acl = IAccessControl(authoriser());
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        if (!acl.hasRole(keccak256("DEPOSIT"), orchestrator)) {
            revert OrchestratorPathNotEnabled(orchestrator, keccak256("DEPOSIT"));
        }
        if (!acl.hasRole(keccak256("WITHDRAW"), orchestrator)) {
            revert OrchestratorPathNotEnabled(orchestrator, keccak256("WITHDRAW"));
        }
        if (!IAccessControl(orchestrator).hasRole(keccak256("MINT"), SERVICE_SIGNER)) {
            revert OrchestratorPathNotEnabled(SERVICE_SIGNER, keccak256("MINT"));
        }
        if (!IAccessControl(orchestrator).hasRole(keccak256("BURN"), SERVICE_SIGNER)) {
            revert OrchestratorPathNotEnabled(SERVICE_SIGNER, keccak256("BURN"));
        }
        if (!acl.hasRole(keccak256("DEPOSIT_ADMIN"), timelock())) {
            revert TimelockMissingRoleAdminForRetire(keccak256("DEPOSIT_ADMIN"));
        }
        if (!acl.hasRole(keccak256("WITHDRAW_ADMIN"), timelock())) {
            revert TimelockMissingRoleAdminForRetire(keccak256("WITHDRAW_ADMIN"));
        }
        if (!acl.hasRole(keccak256("DEPOSIT"), SERVICE_SIGNER)) {
            revert DirectSignerRoleAlreadyRetired(keccak256("DEPOSIT"));
        }
        if (!acl.hasRole(keccak256("WITHDRAW"), SERVICE_SIGNER)) {
            revert DirectSignerRoleAlreadyRetired(keccak256("WITHDRAW"));
        }
        bytes32 head = LibMigrationRegistry.head(timelock(), LibRbacMigration.STOX_RBAC_NAMESPACE);
        if (head != retireDirectSignerRolesDeclaration().prerequisites[0].migration) {
            revert UnexpectedRetireMigrationLine(head);
        }
        if (TimelockController(payable(timelock())).isOperation(operationId())) {
            revert RetirementAlreadyScheduled(operationId());
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe schedules the batch, with the timelock's minimum delay.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch();
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({
            to: timelock(),
            value: 0,
            data: abi.encodeCall(
                TimelockController.scheduleBatch,
                (targets, values, payloads, bytes32(0), RETIRE_SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
            ),
            operation: Enum.Operation.Call
        });
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Scheduled: pending, and not ready inside the delay.
    function assertPostState() internal view override {
        TimelockController controller = TimelockController(payable(timelock()));
        bytes32 id = operationId();
        if (!controller.isOperationPending(id) || controller.isOperationReady(id)) {
            revert RetirementNotPendingInsideDelay(id);
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev On a snapshot: after the delay an address with no role executes the
    /// batch, and the signer holds neither direct role, the orchestrator path
    /// is intact and the record is the timelock's, stamped when it landed.
    function assertReversible() internal override {
        uint256 scheduled = vm.snapshotState();
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch();
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.prank(address(0xdead));
        TimelockController(payable(timelock())).executeBatch(targets, values, payloads, bytes32(0), RETIRE_SALT);
        IAccessControl acl = IAccessControl(authoriser());
        if (acl.hasRole(keccak256("DEPOSIT"), SERVICE_SIGNER)) revert RetirementPostStateMismatch("DEPOSIT");
        if (acl.hasRole(keccak256("WITHDRAW"), SERVICE_SIGNER)) revert RetirementPostStateMismatch("WITHDRAW");
        if (!acl.hasRole(keccak256("CERTIFY"), SERVICE_SIGNER)) revert RetirementPostStateMismatch("CERTIFY");
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        if (!acl.hasRole(keccak256("DEPOSIT"), orchestrator) || !acl.hasRole(keccak256("WITHDRAW"), orchestrator)) {
            revert RetirementPostStateMismatch("orchestrator path");
        }
        ScriptDeclaration memory declared = retireDirectSignerRolesDeclaration();
        // forge-lint: disable-next-line(block-timestamp)
        if (LibMigrationRegistry.applied(timelock(), declared.namespace, declared.id) != block.timestamp) {
            revert RetirementPostStateMismatch("record");
        }
        if (LibMigrationRegistry.head(timelock(), declared.namespace) != declared.id) {
            revert RetirementPostStateMismatch("line head");
        }
        console2.log("Retirement proven on the fork: schedule -> 48h -> execute by a roleless address");
        vm.revertToState(scheduled);
    }
}
