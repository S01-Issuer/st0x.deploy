// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";
import {LibStoxMigrations} from "./LibStoxMigrations.sol";
import {LibBeaconInvariants} from "./LibBeaconInvariants.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";
import {IST0xOrchestratorV1} from "../interface/IST0xOrchestratorV1.sol";

/// @notice The orchestrator beacon-set deployer has no runtime code at its
/// pinned 0.1.30 address on the active chain.
/// @param setDeployer The pinned deployer address that is missing.
error OrchestratorSetDeployerMissing(address setDeployer);

/// @notice The beacon the set deployer reports does not match the pinned
/// beacon address.
/// @param expected The pinned beacon address.
/// @param actual The beacon the set deployer reports.
error OrchestratorBeaconMismatch(address expected, address actual);

/// @notice The pinned orchestrator instance has no runtime code on the
/// active chain.
/// @param instance The pinned instance address.
error OrchestratorInstanceMissing(address instance);

/// @notice The expected admin does not hold `DEFAULT_ADMIN_ROLE` on the
/// orchestrator instance: it is ungovernable, or governed by the wrong key.
/// @param instance The orchestrator instance inspected.
/// @param expectedAdmin The address that must hold `DEFAULT_ADMIN_ROLE`.
error OrchestratorAdminMissing(address instance, address expectedAdmin);

/// @notice An address holds a role on the orchestrator instance that the
/// recorded migrations say it must not.
/// @param instance The orchestrator instance inspected.
/// @param role The role.
/// @param holder The address that holds it.
error OrchestratorUnexpectedRoleHolder(address instance, bytes32 role, address holder);

/// @notice An address the recorded migrations say holds a role on the
/// orchestrator instance does not.
/// @param instance The orchestrator instance inspected.
/// @param role The role.
/// @param holder The address that must hold it.
error OrchestratorRoleMissing(address instance, bytes32 role, address holder);

/// @notice An operating role on the orchestrator is administered by a role
/// other than `DEFAULT_ADMIN_ROLE`.
/// @param instance The orchestrator instance inspected.
/// @param role The operating role.
/// @param adminRole The role that administers it.
error OrchestratorRoleAdminUnexpected(address instance, bytes32 role, bytes32 adminRole);

/// @notice The orchestrator instance's vault-logic version lock does not
/// pass: the OARV beacon-set deployer it was built against reports
/// implementations other than the ones the orchestrator was compiled for,
/// so `mint`/`burn` revert.
/// @param instance The orchestrator instance inspected.
error OrchestratorVaultLogicUnexpected(address instance);

/// @title LibOrchestratorInvariants
/// @notice Pins and live-state invariants for the ST0x orchestrator
/// instance — the orchestrator analogue of the token pins in
/// `LibTokenInvariants` and the beacon pins in `LibProdBeacons*`.
///
/// The whole surface is deterministic, so it is pinned up front rather than
/// hydrated from a broadcast: the beacon-set deployer is a Zoltu deploy (the
/// 0.1.30 pin), the beacon is the deployer constructor's first `CREATE`
/// (deployer nonce 1), and the first `deploy()` call's `BeaconProxy` is the
/// deployer's second `CREATE` (nonce 2). Identical deployer address +
/// identical nonces ⇒ identical beacon and instance addresses on every
/// chain.
library LibOrchestratorInvariants {
    /// @notice The `UpgradeableBeacon` created by the 0.1.30
    /// `ST0xOrchestratorBeaconSetDeployer`'s constructor — its `CREATE` at
    /// nonce 1, so the same address on every chain the deployer is on.
    /// Aliases the `LibProdDeployV4` pin (single source of truth, emitted by
    /// `BuildPointers`).
    address internal constant ST0X_ORCHESTRATOR_BEACON = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON;

    /// @notice The production orchestrator instance: the `BeaconProxy` minted
    /// by the FIRST `deploy()` call on the 0.1.30 beacon-set deployer — its
    /// `CREATE` at nonce 2, so the same address on every chain where the
    /// instance is the first one deployed.
    /// `20260818-deploy-orchestrator` refuses to broadcast against a deployer
    /// whose nonce shows an earlier `deploy()`, so a pinned instance is
    /// always this address. Aliases the `LibProdDeployV4` pin (single source
    /// of truth, emitted by `BuildPointers`).
    address internal constant ST0X_ORCHESTRATOR_INSTANCE = LibProdDeployV4.ST0X_ORCHESTRATOR_INSTANCE;

    /// @notice `keccak256("MINT")`, the orchestrator's mint role.
    bytes32 internal constant MINT_ROLE = keccak256("MINT");

    /// @notice `keccak256("BURN")`, the orchestrator's burn role.
    bytes32 internal constant BURN_ROLE = keccak256("BURN");

    /// @notice `keccak256("EMERGENCY")`, the orchestrator's recovery role.
    bytes32 internal constant EMERGENCY_ROLE = keccak256("EMERGENCY");

    /// @notice Assert the orchestrator beacon set on the active chain: the
    /// 0.1.30 beacon-set deployer is live, reports the pinned beacon, the
    /// beacon points at the audited 0.1.30 orchestrator implementation, and
    /// the chain's governance timelock owns the beacon.
    function assertBeaconSet() internal view {
        address setDeployer = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30;
        if (setDeployer.code.length == 0) {
            revert OrchestratorSetDeployerMissing(setDeployer);
        }

        address beacon = address(ST0xOrchestratorBeaconSetDeployerLike(setDeployer).iOrchestratorBeacon());
        if (beacon != ST0X_ORCHESTRATOR_BEACON) {
            revert OrchestratorBeaconMismatch(ST0X_ORCHESTRATOR_BEACON, beacon);
        }

        // Codehash first, then owner (the chain's timelock) and implementation,
        // through the shared beacon check.
        LibBeaconInvariants.assertBeaconInvariants(
            beacon,
            LibTimelockInvariants.timelockForChainId(block.chainid),
            LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30,
            LibBeaconInvariants.UPGRADEABLE_BEACON_CODEHASH_0_1_30
        );
    }

    /// @notice Assert the pinned orchestrator instance on the active chain:
    /// it has code, its vault-logic version lock passes (so `mint`/`burn`
    /// are operable), and its roles are exactly what the migrations the
    /// chain's Safe has recorded imply:
    ///
    /// - `DEFAULT_ADMIN_ROLE` is held by the governance timelock and not the
    ///   Safe once `ORCHESTRATOR_ADMIN_TO_TIMELOCK` is recorded, and by the
    ///   Safe and not the timelock before.
    /// - `EMERGENCY_ROLE` is held by the Safe once `ORCHESTRATOR_EMERGENCY`
    ///   is recorded, and not before. The timelock never holds it: recovery
    ///   is an operation, not admin power.
    /// - Neither principal holds `MINT_ROLE` or `BURN_ROLE`: those are the
    ///   service signers' operations.
    /// - `DEFAULT_ADMIN_ROLE`, `MINT_ROLE`, `BURN_ROLE` and `EMERGENCY_ROLE`
    ///   are administered by `DEFAULT_ADMIN_ROLE`, so whoever holds it
    ///   decides every grant.
    ///
    /// Role membership is not enumerable on the orchestrator, so only the
    /// two governance principals are checked; any other holder is invisible
    /// here.
    /// @param chainSafe The chain's token-owner Safe, which is also the
    /// writer of the migration records.
    function assertInstance(address chainSafe) internal view {
        address instance = ST0X_ORCHESTRATOR_INSTANCE;
        if (instance.code.length == 0) {
            revert OrchestratorInstanceMissing(instance);
        }
        if (!IST0xOrchestratorV1(instance).vaultLogicIsExpected()) {
            revert OrchestratorVaultLogicUnexpected(instance);
        }

        IAccessControl acl = IAccessControl(instance);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);

        // DEFAULT_ADMIN_ROLE is 0x00 in OZ AccessControl.
        bool adminMoved = LibStoxMigrations.applied(chainSafe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) != 0;
        if (adminMoved) {
            assertHolds(acl, bytes32(0), timelock);
            assertDoesNotHold(acl, bytes32(0), chainSafe);
        } else {
            assertHolds(acl, bytes32(0), chainSafe);
            assertDoesNotHold(acl, bytes32(0), timelock);
        }

        if (LibStoxMigrations.applied(chainSafe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) != 0) {
            assertHolds(acl, EMERGENCY_ROLE, chainSafe);
        } else {
            assertDoesNotHold(acl, EMERGENCY_ROLE, chainSafe);
        }
        assertDoesNotHold(acl, EMERGENCY_ROLE, timelock);

        // Minting and burning are the service signers' operations; neither
        // governance principal ever holds them.
        assertDoesNotHold(acl, MINT_ROLE, chainSafe);
        assertDoesNotHold(acl, MINT_ROLE, timelock);
        assertDoesNotHold(acl, BURN_ROLE, chainSafe);
        assertDoesNotHold(acl, BURN_ROLE, timelock);

        // `DEFAULT_ADMIN_ROLE` must administer itself, or a holder of its admin
        // role could take it without the governance principal.
        assertAdministeredByDefaultAdmin(acl, bytes32(0));
        assertAdministeredByDefaultAdmin(acl, MINT_ROLE);
        assertAdministeredByDefaultAdmin(acl, BURN_ROLE);
        assertAdministeredByDefaultAdmin(acl, EMERGENCY_ROLE);
    }

    /// @notice Revert unless `holder` holds `role` on the instance.
    /// @param acl The instance's access-control surface.
    /// @param role The role.
    /// @param holder The address that must hold it.
    function assertHolds(IAccessControl acl, bytes32 role, address holder) private view {
        if (!acl.hasRole(role, holder)) {
            if (role == bytes32(0)) {
                revert OrchestratorAdminMissing(address(acl), holder);
            }
            revert OrchestratorRoleMissing(address(acl), role, holder);
        }
    }

    /// @notice Revert if `holder` holds `role` on the instance.
    /// @param acl The instance's access-control surface.
    /// @param role The role.
    /// @param holder The address that must not hold it.
    function assertDoesNotHold(IAccessControl acl, bytes32 role, address holder) private view {
        if (acl.hasRole(role, holder)) {
            revert OrchestratorUnexpectedRoleHolder(address(acl), role, holder);
        }
    }

    /// @notice Revert unless `role` is administered by `DEFAULT_ADMIN_ROLE`.
    /// @param acl The instance's access-control surface.
    /// @param role The operating role.
    function assertAdministeredByDefaultAdmin(IAccessControl acl, bytes32 role) private view {
        bytes32 adminRole = acl.getRoleAdmin(role);
        if (adminRole != bytes32(0)) {
            revert OrchestratorRoleAdminUnexpected(address(acl), role, adminRole);
        }
    }
}

/// @dev Local mirror of the set deployer's `iOrchestratorBeacon` immutable
/// getter — `IST0xOrchestratorBeaconSetDeployerV1` carries only the
/// `deploy` surface, and the getter is a concrete-contract detail the
/// interface deliberately omits.
interface ST0xOrchestratorBeaconSetDeployerLike {
    function iOrchestratorBeacon() external view returns (IBeacon);
}
