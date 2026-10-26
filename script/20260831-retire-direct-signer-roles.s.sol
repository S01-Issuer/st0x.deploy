// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.22/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.22/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.22/src/lib/LibSafeFork.sol";

import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {orchestratorAdminToTimelockDeclaration} from "./20261006-orchestrator-admin-to-timelock.s.sol";

/// @notice The orchestrator mint/burn path is not fully enabled on this
/// chain — retiring the signer's direct roles now would leave NO working
/// mint/burn path.
/// @param holder The principal missing a role.
/// @param role The role it must hold before retirement can be authored.
error OrchestratorPathNotEnabled(address holder, bytes32 role);

/// @notice The timelock does not hold the `_ADMIN` role needed to revoke a
/// role the signer still holds.
/// @param adminRole The missing `_ADMIN` role.
error TimelockMissingRoleAdminForRetire(bytes32 adminRole);

/// @notice The retirement is scheduled and still inside its delay.
/// @param id The timelock operation.
error RetireInsideDelay(bytes32 id);

/// @notice After the schedule bundle, the retirement is not pending inside
/// its delay.
/// @param id The timelock operation.
error RetireNotScheduled(bytes32 id);

/// @notice The re-grant through the timelock did not restore the signer's
/// direct `DEPOSIT`.
error RegrantNotRestored();

/// @notice This script's declaration: the line's record after the
/// orchestrator admin move.
/// @return The declaration.
function retireDirectSignerRolesDeclaration() pure returns (ScriptDeclaration memory) {
    return LibStoxMigrations.migrationOnto(
        keccak256("script/20260831-retire-direct-signer-roles.s.sol"), orchestratorAdminToTimelockDeclaration().id
    );
}

/// @title RetireDirectSignerRoles
/// @notice Authors the per-chain Safe bundles that retire the service
/// signer's DIRECT `DEPOSIT` and `WITHDRAW` on the authoriser, leaving the
/// orchestrator as the only mint/burn path the signer can drive. The
/// authoriser's `_ADMIN` roles are on the governance timelock, so the
/// retirement is one timelock batch:
///
/// 1. `authoriser.revokeRole(role, signer)` for each of `DEPOSIT` and
///    `WITHDRAW` the signer still holds.
/// 2. `registry.applyMigrationV3(WRITER, NAMESPACE, <this script>,
///    [orchestrator admin move])`, written by the timelock as
///    `LibStoxMigrations.WRITER`'s approved delegate, so the record lands
///    with the revokes whoever executes the matured batch.
///
/// The bundle is the stage the timelock is at: `scheduleBatch` when the batch
/// is not scheduled, `executeBatch` once it is ready. A batch inside its delay
/// refuses (`RetireInsideDelay`).
///
/// Deliberately untouched: the signer's `CERTIFY` (the orchestrator has no
/// certify surface) and the Safe's own three direct action roles.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20260831-retire-direct-signer-roles` per chain, once to schedule
/// and again after `TIMELOCK_MIN_DELAY` to execute. Pre-flight refuses unless
/// the orchestrator path is FULLY enabled (`OrchestratorPathNotEnabled`).
contract RetireDirectSignerRoles is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return retireDirectSignerRolesDeclaration();
    }

    /// @notice The service signer whose direct vault access retires.
    address internal constant SERVICE_SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

    /// @notice The orchestrator's operational roles (audited 0.1.30 source).
    bytes32 internal constant ORCHESTRATOR_MINT_ROLE = keccak256("MINT");
    bytes32 internal constant ORCHESTRATOR_BURN_ROLE = keccak256("BURN");

    /// @notice The retirement batch's salt.
    bytes32 internal constant RETIRE_SALT = keccak256("st0x.retire-direct-signer-roles.20260831");

    /// @notice Salt for the fork-only re-grant proof.
    bytes32 internal constant PROOF_SALT = keccak256("st0x.retire-direct-signer-roles.proof");

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x retire: service signer's direct vault roles, through the timelock";
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
    function timelock() internal view returns (TimelockController) {
        return TimelockController(payable(LibTimelockInvariants.timelockForChainId(block.chainid)));
    }

    /// @notice The burn-in gate: the orchestrator holds both vault roles on
    /// the authoriser and the signer holds both operational roles on the
    /// orchestrator. Reverts `OrchestratorPathNotEnabled` naming the first
    /// missing (holder, role).
    /// @param acl The authoriser's access-control surface.
    /// @param orchestrator The orchestrator instance.
    function assertOrchestratorPathEnabled(IAccessControl acl, address orchestrator) internal view {
        if (!acl.hasRole(keccak256("DEPOSIT"), orchestrator)) {
            revert OrchestratorPathNotEnabled(orchestrator, keccak256("DEPOSIT"));
        }
        if (!acl.hasRole(keccak256("WITHDRAW"), orchestrator)) {
            revert OrchestratorPathNotEnabled(orchestrator, keccak256("WITHDRAW"));
        }
        IAccessControl orch = IAccessControl(orchestrator);
        if (!orch.hasRole(ORCHESTRATOR_MINT_ROLE, SERVICE_SIGNER)) {
            revert OrchestratorPathNotEnabled(SERVICE_SIGNER, ORCHESTRATOR_MINT_ROLE);
        }
        if (!orch.hasRole(ORCHESTRATOR_BURN_ROLE, SERVICE_SIGNER)) {
            revert OrchestratorPathNotEnabled(SERVICE_SIGNER, ORCHESTRATOR_BURN_ROLE);
        }
    }

    /// @notice The retirement batch from live state: one `revokeRole` per
    /// direct role the signer still holds, then the record. Refuses a revoke
    /// the timelock cannot make.
    /// @param authoriser The chain's authoriser clone.
    /// @param controller The chain's governance timelock.
    /// @return The batch's targets.
    /// @return The batch's values.
    /// @return The batch's payloads.
    function operation(address authoriser, address controller)
        internal
        view
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {
        IAccessControl acl = IAccessControl(authoriser);
        bytes32[2] memory roles = [keccak256("DEPOSIT"), keccak256("WITHDRAW")];
        bytes32[2] memory admins = [keccak256("DEPOSIT_ADMIN"), keccak256("WITHDRAW_ADMIN")];
        uint256 count = 0;
        for (uint256 i = 0; i < roles.length; i++) {
            if (acl.hasRole(roles[i], SERVICE_SIGNER)) {
                if (!acl.hasRole(admins[i], controller)) revert TimelockMissingRoleAdminForRetire(admins[i]);
                count++;
            }
        }
        address[] memory targets = new address[](count + 1);
        uint256[] memory values = new uint256[](count + 1);
        bytes[] memory payloads = new bytes[](count + 1);
        uint256 next = 0;
        for (uint256 i = 0; i < roles.length; i++) {
            if (acl.hasRole(roles[i], SERVICE_SIGNER)) {
                targets[next] = authoriser;
                payloads[next] = abi.encodeCall(IAccessControl.revokeRole, (roles[i], SERVICE_SIGNER));
                next++;
            }
        }
        (targets[count], payloads[count]) = LibStoxMigrations.recordCall(retireDirectSignerRolesDeclaration());
        return (targets, values, payloads);
    }

    /// @notice The live retirement batch's timelock operation id.
    /// @return The id.
    function operationId() internal view returns (bytes32) {
        TimelockController controller = timelock();
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            operation(LibAuthoriserInvariants.activeChainAuthoriser(), address(controller));
        return controller.hashOperationBatch(targets, values, payloads, bytes32(0), RETIRE_SALT);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe, timelock, orchestrator and grant map are what this repo
    /// pins, the orchestrator path is enabled, this is the line's next record
    /// and the timelock may write it, and the batch is not inside its delay.
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address controller = address(timelock());
        LibTimelockInvariants.assertTimelockState(controller, chainSafe);
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        LibOrchestratorInvariants.assertBeaconSet();
        LibOrchestratorInvariants.assertInstance();
        assertOrchestratorPathEnabled(IAccessControl(authoriser), LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);
        LibAuthoriserInvariants.assertExpectedGrants(authoriser, chainSafe, controller);
        LibStoxMigrations.assertNext(retireDirectSignerRolesDeclaration(), controller);

        bytes32 id = operationId();
        if (timelock().isOperationPending(id) && !timelock().isOperationReady(id)) revert RetireInsideDelay(id);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev `scheduleBatch` if the batch is not scheduled, else
    /// `executeBatch`.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        TimelockController controller = timelock();
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            operation(LibAuthoriserInvariants.activeChainAuthoriser(), address(controller));
        bytes memory data = controller.isOperation(
                controller.hashOperationBatch(targets, values, payloads, bytes32(0), RETIRE_SALT)
            )
            ? abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, bytes32(0), RETIRE_SALT))
            : abi.encodeCall(
                TimelockController.scheduleBatch,
                (targets, values, payloads, bytes32(0), RETIRE_SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
            );
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({to: address(controller), value: 0, data: data, operation: Enum.Operation.Call});
        return txs;
    }

    /// @notice The retired state: the signer holds neither direct vault role,
    /// every row of the grant map survives, and the orchestrator path is
    /// intact.
    /// @param acl The authoriser's access-control surface.
    /// @param orchestrator The orchestrator instance.
    /// @param safeAddr The chain's token-owner Safe.
    function assertPostRetireState(IAccessControl acl, address orchestrator, address safeAddr) internal view {
        require(
            !acl.hasRole(keccak256("DEPOSIT"), SERVICE_SIGNER) && !acl.hasRole(keccak256("WITHDRAW"), SERVICE_SIGNER),
            "RetireDirectSignerRoles: signer still holds a direct vault role"
        );
        RoleGrant[] memory all =
            LibAuthoriserInvariants.expectedGrants(safeAddr, LibTimelockInvariants.timelockForChainId(block.chainid));
        for (uint256 i = 0; i < all.length; i++) {
            require(
                acl.hasRole(all[i].role, all[i].grantee),
                "RetireDirectSignerRoles: retirement disturbed an unrelated grant"
            );
        }
        assertOrchestratorPathEnabled(acl, orchestrator);
    }

    /// @notice The executed batch's state: its record and the retired state.
    function assertExecuted() internal view {
        LibStoxMigrations.assertRecorded(retireDirectSignerRolesDeclaration());
        assertPostRetireState(
            IAccessControl(LibAuthoriserInvariants.activeChainAuthoriser()),
            LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE,
            address(safe())
        );
    }

    /// @inheritdoc SafeBundleScript
    /// @dev After `executeBatch`, the executed state; after `scheduleBatch`,
    /// the batch pending inside its delay. The Safe keeps its policy.
    function assertPostState() internal view override {
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
        if (LibStoxMigrations.applied(retireDirectSignerRolesDeclaration().id) != 0) {
            assertExecuted();
            return;
        }
        bytes32 id = operationId();
        if (!timelock().isOperationPending(id) || timelock().isOperationReady(id)) revert RetireNotScheduled(id);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev After `scheduleBatch`, the batch executes from a roleless address
    /// once the delay has run and leaves the executed state. Then the Safe can
    /// restore the signer's direct `DEPOSIT` through the timelock. The fork
    /// returns to the post-bundle state.
    function assertReversible() internal override {
        uint256 postBundle = vm.snapshotState();
        TimelockController controller = timelock();
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        if (LibStoxMigrations.applied(retireDirectSignerRolesDeclaration().id) == 0) {
            (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
                operation(authoriser, address(controller));
            // forge-lint: disable-next-line(block-timestamp)
            vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
            vm.prank(address(0xdead));
            controller.executeBatch(targets, values, payloads, bytes32(0), RETIRE_SALT);
            assertExecuted();
        }

        bytes memory regrant =
            abi.encodeCall(IAccessControl.grantRole, (keccak256("DEPOSIT"), SERVICE_SIGNER));
        LibSafeFork.simulateNPlus1(
            vm,
            safe(),
            address(controller),
            abi.encodeCall(
                TimelockController.schedule,
                (authoriser, 0, regrant, bytes32(0), PROOF_SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
            )
        );
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.prank(address(0xdead));
        controller.execute(authoriser, 0, regrant, bytes32(0), PROOF_SALT);
        if (!IAccessControl(authoriser).hasRole(keccak256("DEPOSIT"), SERVICE_SIGNER)) revert RegrantNotRestored();
        console2.log("Retirement proven: executed through the timelock, and reversible through it");
        vm.revertToState(postBundle);
    }
}
