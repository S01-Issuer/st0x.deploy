// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";
import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {LibStoxMigrations} from "./LibStoxMigrations.sol";
import {LibBeaconInvariants} from "./LibBeaconInvariants.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";
import {LibAuthoriserInvariants} from "./LibAuthoriserInvariants.sol";
import {RoleGrant} from "./RoleGrant.sol";
import {IST0xOrchestratorV1} from "../interface/IST0xOrchestratorV1.sol";
import {IST0xOrchestratorV2} from "../interface/IST0xOrchestratorV2.sol";
import {
    ST0xOrchestrator,
    ORCHESTRATOR_MINT_ROLE,
    ORCHESTRATOR_MINT_ADMIN_ROLE,
    ORCHESTRATOR_BURN_ROLE,
    ORCHESTRATOR_BURN_ADMIN_ROLE,
    ORCHESTRATOR_EMERGENCY_ROLE,
    ORCHESTRATOR_EMERGENCY_ADMIN_ROLE
} from "../concrete/ST0xOrchestrator.sol";
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

/// @notice An address the recorded migrations say holds a role on the
/// orchestrator instance does not.
/// @param instance The orchestrator instance inspected.
/// @param role The role.
/// @param holder The address that must hold it.
error OrchestratorRoleMissing(address instance, bytes32 role, address holder);

/// @notice A principal that must not hold a role on an orchestrator instance
/// holds it.
/// @param instance The orchestrator instance inspected.
/// @param role The role that must not be held.
/// @param holder The principal that holds it.
error OrchestratorUnexpectedRoleHolder(address instance, bytes32 role, address holder);

/// @notice A role on an orchestrator instance is administered by a role
/// other than the expected one.
/// @param instance The orchestrator instance inspected.
/// @param role The role whose admin was read.
/// @param expected The role that must administer it.
/// @param actual The role `getRoleAdmin` returned.
error OrchestratorRoleAdminUnexpected(address instance, bytes32 role, bytes32 expected, bytes32 actual);

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
    /// are operable), every role is administered by `DEFAULT_ADMIN_ROLE`,
    /// and it holds each `expectedGrants` pair whose migration the chain's
    /// Safe has recorded (`migrationRecorded`).
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

        RoleGrant[] memory expected = expectedGrants(chainSafe, timelock);
        for (uint256 i = 0; i < expected.length; i++) {
            if (migrationRecorded(chainSafe, expected[i].role)) {
                assertHolds(acl, expected[i]);
            }
        }

        assertAdministeredBy(acl, bytes32(0), bytes32(0));
        assertAdministeredBy(acl, ST0xOrchestrator(payable(instance)).MINT_ROLE(), bytes32(0));
        assertAdministeredBy(acl, ST0xOrchestrator(payable(instance)).BURN_ROLE(), bytes32(0));
        assertAdministeredBy(acl, ST0xOrchestrator(payable(instance)).EMERGENCY_ROLE(), bytes32(0));
    }

    /// @notice Whether the chain's Safe has recorded the migration that
    /// grants `role` its expected holder: `ORCHESTRATOR_ADMIN_TO_TIMELOCK`
    /// for `DEFAULT_ADMIN_ROLE`, `ORCHESTRATOR_EMERGENCY` for `EMERGENCY`;
    /// no migration grants any other role, so it is never recorded.
    /// @param chainSafe The chain's token-owner Safe.
    /// @param role The role.
    /// @return Whether the migration is recorded.
    function migrationRecorded(address chainSafe, bytes32 role) private view returns (bool) {
        if (role == bytes32(0)) {
            return LibStoxMigrations.applied(chainSafe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) != 0;
        }
        if (role == keccak256("EMERGENCY")) {
            return LibStoxMigrations.applied(chainSafe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY) != 0;
        }
        return false;
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

    /// @notice Revert unless the instance carries `grant`.
    /// @param acl The instance's access-control surface.
    /// @param grant The pair.
    function assertHolds(IAccessControl acl, RoleGrant memory grant) private view {
        if (!acl.hasRole(grant.role, grant.grantee)) {
            if (grant.role == bytes32(0)) {
                revert OrchestratorAdminMissing(address(acl), grant.grantee);
            }
            revert OrchestratorRoleMissing(address(acl), grant.role, grant.grantee);
        }
    }

    /// @notice The beacon the mint-caps orchestrator's beacon-set deployer
    /// creates in its constructor: its `CREATE` at nonce 1. The deployer is
    /// the current-release Zoltu deploy, so this is the same on every chain.
    /// @return The mint-caps orchestrator beacon.
    function mintCapsBeacon() internal pure returns (address) {
        return createAddress(LibProdDeployCurrent.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER, 1);
    }

    /// @notice The mint-caps orchestrator instance: the `BeaconProxy` the
    /// first `deploy()` on its beacon-set deployer creates, its `CREATE` at
    /// nonce 2. It runs alongside `ST0X_ORCHESTRATOR_INSTANCE` while it
    /// bootstraps.
    /// @return The mint-caps orchestrator instance.
    function mintCapsInstance() internal pure returns (address) {
        return createAddress(LibProdDeployCurrent.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER, 2);
    }

    /// @notice The address `deployer` creates with `CREATE` at `nonce`, for a
    /// nonce in `[1, 0x7f]` (one RLP byte).
    /// @param deployer The creating account.
    /// @param nonce The creating account's nonce.
    /// @return The created address.
    function createAddress(address deployer, uint8 nonce) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, nonce)))));
    }

    /// @notice Assert the mint-caps orchestrator's beacon set on the active
    /// chain: the current-release beacon-set deployer is live and reports
    /// `mintCapsBeacon()`, and that beacon is this build's
    /// `UpgradeableBeacon`, points at the current-release orchestrator
    /// implementation and is owned by the chain's governance timelock.
    function assertMintCapsBeaconSet() internal view {
        address setDeployer = LibProdDeployCurrent.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER;
        if (setDeployer.code.length == 0) {
            revert OrchestratorSetDeployerMissing(setDeployer);
        }
        address beacon = address(ST0xOrchestratorBeaconSetDeployerLike(setDeployer).iOrchestratorBeacon());
        if (beacon != mintCapsBeacon()) {
            revert OrchestratorBeaconMismatch(mintCapsBeacon(), beacon);
        }
        LibBeaconInvariants.assertBeaconInvariants(
            beacon,
            LibTimelockInvariants.timelockForChainId(block.chainid),
            LibProdDeployCurrent.ST0X_ORCHESTRATOR,
            keccak256(type(UpgradeableBeacon).runtimeCode)
        );
    }

    /// @notice Assert the mint-caps orchestrator instance on the active
    /// chain:
    ///
    /// - it has code and its vault-logic version lock passes;
    /// - the chain's governance timelock holds `DEFAULT_ADMIN_ROLE`,
    ///   `MINT_ADMIN_ROLE`, `BURN_ADMIN_ROLE` and `EMERGENCY_ADMIN_ROLE`, and
    ///   no operating role;
    /// - each operating role is administered by its admin role, each admin
    ///   role by itself, and `DEFAULT_ADMIN_ROLE` by itself;
    /// - `chainSafe` holds no admin role, `MINT_ROLE` or `BURN_ROLE`, and the
    ///   deploy key holds no role at all.
    ///
    /// The Safe's `EMERGENCY_ROLE` is not asserted either way: it is an
    /// operating role `EMERGENCY_ADMIN_ROLE` may grant it.
    ///
    /// Role membership is not enumerable on the orchestrator, so only these
    /// three principals are checked.
    /// @param chainSafe The chain's token-owner Safe.
    function assertMintCapsInstance(address chainSafe) internal view {
        address instance = mintCapsInstance();
        if (instance.code.length == 0) {
            revert OrchestratorInstanceMissing(instance);
        }
        if (!IST0xOrchestratorV2(instance).vaultLogicIsExpected()) {
            revert OrchestratorVaultLogicUnexpected(instance);
        }

        IAccessControl acl = IAccessControl(instance);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address deployKey = LibProdDeployCurrent.BEACON_INITIAL_OWNER;

        bytes32[4] memory adminRoles = [
            // DEFAULT_ADMIN_ROLE is 0x00 in OZ AccessControl.
            bytes32(0), ORCHESTRATOR_MINT_ADMIN_ROLE, ORCHESTRATOR_BURN_ADMIN_ROLE, ORCHESTRATOR_EMERGENCY_ADMIN_ROLE
        ];
        for (uint256 i = 0; i < adminRoles.length; i++) {
            assertHolds(acl, adminRoles[i], timelock);
            assertDoesNotHold(acl, adminRoles[i], chainSafe);
            assertDoesNotHold(acl, adminRoles[i], deployKey);
        }

        bytes32 mintRole = ORCHESTRATOR_MINT_ROLE;
        bytes32 burnRole = ORCHESTRATOR_BURN_ROLE;
        bytes32 emergencyRole = ORCHESTRATOR_EMERGENCY_ROLE;
        bytes32[3] memory operatingRoles = [mintRole, burnRole, emergencyRole];
        for (uint256 i = 0; i < operatingRoles.length; i++) {
            assertDoesNotHold(acl, operatingRoles[i], timelock);
            assertDoesNotHold(acl, operatingRoles[i], deployKey);
        }
        assertDoesNotHold(acl, mintRole, chainSafe);
        assertDoesNotHold(acl, burnRole, chainSafe);

        assertAdministeredBy(acl, adminRoles[0], adminRoles[0]);
        for (uint256 i = 0; i < operatingRoles.length; i++) {
            assertAdministeredBy(acl, operatingRoles[i], adminRoles[i + 1]);
            assertAdministeredBy(acl, adminRoles[i + 1], adminRoles[i + 1]);
        }
    }

    /// @notice Revert unless `holder` holds `role` on `acl`.
    /// @param acl The orchestrator instance.
    /// @param role The role.
    /// @param holder The principal.
    function assertHolds(IAccessControl acl, bytes32 role, address holder) private view {
        if (!acl.hasRole(role, holder)) {
            revert OrchestratorRoleMissing(address(acl), role, holder);
        }
    }

    /// @notice Revert if `holder` holds `role` on `acl`.
    /// @param acl The orchestrator instance.
    /// @param role The role.
    /// @param holder The principal.
    function assertDoesNotHold(IAccessControl acl, bytes32 role, address holder) private view {
        if (acl.hasRole(role, holder)) {
            revert OrchestratorUnexpectedRoleHolder(address(acl), role, holder);
        }
    }

    /// @notice Revert unless `role` is administered by `adminRole` on `acl`.
    /// @param acl The orchestrator instance.
    /// @param role The role whose admin is read.
    /// @param adminRole The role that must administer it.
    function assertAdministeredBy(IAccessControl acl, bytes32 role, bytes32 adminRole) private view {
        bytes32 actual = acl.getRoleAdmin(role);
        if (actual != adminRole) {
            revert OrchestratorRoleAdminUnexpected(address(acl), role, adminRole, actual);
        }
    }
}

/// @dev Local mirror of the set deployer's `iOrchestratorBeacon` immutable
/// getter; `IST0xOrchestratorBeaconSetDeployerV1` and `V2` carry only the
/// `deploy` surface.
interface ST0xOrchestratorBeaconSetDeployerLike {
    function iOrchestratorBeacon() external view returns (IBeacon);
}
