// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";
import {LibBeaconInvariants} from "./LibBeaconInvariants.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";
import {LibAuthoriserInvariants} from "./LibAuthoriserInvariants.sol";
import {RoleGrant} from "./RoleGrant.sol";
import {IST0xOrchestratorV1} from "../interface/deprecated/IST0xOrchestratorV1.sol";
import {ST0xOrchestrator} from "../concrete/ST0xOrchestrator.sol";

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
    /// `script/Build.sol`).
    address internal constant ST0X_ORCHESTRATOR_BEACON = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON;

    /// @notice The production orchestrator instance: the `BeaconProxy` minted
    /// by the FIRST `deploy()` call on the 0.1.30 beacon-set deployer — its
    /// `CREATE` at nonce 2, so the same address on every chain where the
    /// instance is the first one deployed.
    /// `20260818-deploy-orchestrator` refuses to broadcast against a deployer
    /// whose nonce shows an earlier `deploy()`, so a pinned instance is
    /// always this address. Aliases the `LibProdDeployV4` pin (single source
    /// of truth, emitted by `script/Build.sol`).
    address internal constant ST0X_ORCHESTRATOR_INSTANCE = LibProdDeployV4.ST0X_ORCHESTRATOR_INSTANCE;

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
    /// are operable), and every role is administered by `DEFAULT_ADMIN_ROLE`.
    function assertInstance() internal view {
        address instance = ST0X_ORCHESTRATOR_INSTANCE;
        if (instance.code.length == 0) {
            revert OrchestratorInstanceMissing(instance);
        }
        if (!IST0xOrchestratorV1(instance).vaultLogicIsExpected()) {
            revert OrchestratorVaultLogicUnexpected(instance);
        }

        IAccessControl acl = IAccessControl(instance);
        assertAdministeredByDefaultAdmin(acl, bytes32(0));
        assertAdministeredByDefaultAdmin(acl, ST0xOrchestrator(payable(instance)).MINT_ROLE());
        assertAdministeredByDefaultAdmin(acl, ST0xOrchestrator(payable(instance)).BURN_ROLE());
        assertAdministeredByDefaultAdmin(acl, ST0xOrchestrator(payable(instance)).EMERGENCY_ROLE());
    }

    /// @notice The pairs the orchestrator instance must carry.
    /// @param chainSafe The chain's token-owner Safe.
    /// @param timelock The chain's governance timelock.
    /// @return The expected `(role, grantee)` pairs.
    function expectedGrants(address chainSafe, address timelock) internal pure returns (RoleGrant[] memory) {
        RoleGrant[] memory grants = new RoleGrant[](4);
        grants[0] = RoleGrant(bytes32(0), timelock);
        grants[1] = RoleGrant(keccak256("EMERGENCY"), chainSafe);
        grants[2] = RoleGrant(keccak256("MINT"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
        grants[3] = RoleGrant(keccak256("BURN"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
        return grants;
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
