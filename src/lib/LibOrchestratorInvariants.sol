// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";
import {LibMigrationInvariant} from "./LibMigrationInvariant.sol";
import {IST0xOrchestratorV1} from "../interface/IST0xOrchestratorV1.sol";
import {IST0xOrchestratorV2} from "../interface/IST0xOrchestratorV2.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";
import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {LibTimelockInvariants} from "./LibTimelockInvariants.sol";
import {LibBeaconInvariants} from "./LibBeaconInvariants.sol";
import {
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

/// @notice The orchestrator beacon does not point at the pinned 0.1.30
/// orchestrator implementation.
/// @param expected The pinned 0.1.30 implementation.
/// @param actual The implementation the beacon reports.
error OrchestratorBeaconImplMismatch(address expected, address actual);

/// @notice The pinned orchestrator instance has no runtime code on the
/// active chain.
/// @param instance The pinned instance address.
error OrchestratorInstanceMissing(address instance);

/// @notice The expected admin does not hold `DEFAULT_ADMIN_ROLE` on the
/// orchestrator instance.
/// @param instance The orchestrator instance inspected.
/// @param expectedAdmin The address that must hold `DEFAULT_ADMIN_ROLE`.
error OrchestratorAdminMissing(address instance, address expectedAdmin);

/// @notice The orchestrator instance's vault-logic version lock does not
/// pass: the OARV beacon-set deployer it was built against reports
/// implementations other than the ones the orchestrator was compiled for,
/// so `mint`/`burn` revert.
/// @param instance The orchestrator instance inspected.
error OrchestratorVaultLogicUnexpected(address instance);

/// @notice A principal that must hold a role on an orchestrator instance
/// does not.
/// @param instance The orchestrator instance inspected.
/// @param role The role that must be held.
/// @param holder The principal that must hold it.
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

/// @title LibOrchestratorInvariants
/// @notice Pins and live-state invariants for the ST0x orchestrator
/// instance.
///
/// Every address is deterministic: the beacon-set deployer is a Zoltu deploy
/// (the 0.1.30 pin), the beacon is the deployer constructor's first `CREATE`
/// (deployer nonce 1), and the first `deploy()` call's `BeaconProxy` is the
/// deployer's second `CREATE` (nonce 2), so the beacon and instance addresses
/// are the same on every chain.
library LibOrchestratorInvariants {
    /// @notice The `UpgradeableBeacon` created by the 0.1.30
    /// `ST0xOrchestratorBeaconSetDeployer`'s constructor, its `CREATE` at
    /// nonce 1. Aliases the `LibProdDeployV4` pin.
    address internal constant ST0X_ORCHESTRATOR_BEACON = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON;

    /// @notice The production orchestrator instance: the `BeaconProxy` minted
    /// by the first `deploy()` call on the 0.1.30 beacon-set deployer, its
    /// `CREATE` at nonce 2. Aliases the `LibProdDeployV4` pin.
    address internal constant ST0X_ORCHESTRATOR_INSTANCE = LibProdDeployV4.ST0X_ORCHESTRATOR_INSTANCE;

    /// @notice Unix timestamp (2026-10-01T00:00:00Z) of the orchestrator
    /// beacon owner migration deadline. Until then the deploy EOA or the
    /// chain's token-owner Safe passes as owner; after it only the Safe does
    /// (see `LibMigrationInvariant`).
    uint256 internal constant ST0X_ORCHESTRATOR_BEACON_OWNER_MIGRATION_DEADLINE = 1_790_812_800;

    /// @notice Assert the orchestrator beacon set on the active chain: the
    /// 0.1.30 beacon-set deployer is live, reports the pinned beacon, and the
    /// beacon points at the pinned 0.1.30 orchestrator implementation. The
    /// beacon's owner is asserted through the owner-migration window: the
    /// deploy EOA (`BEACON_INITIAL_OWNER`) or `chainSafe` until the migration
    /// deadline, only `chainSafe` after it.
    /// @param chainSafe The chain's token-owner Safe, the post-migration
    /// beacon owner.
    function assertBeaconSet(address chainSafe) internal view {
        address setDeployer = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30;
        if (setDeployer.code.length == 0) {
            revert OrchestratorSetDeployerMissing(setDeployer);
        }

        address beacon = address(ST0xOrchestratorBeaconSetDeployerLike(setDeployer).iOrchestratorBeacon());
        if (beacon != ST0X_ORCHESTRATOR_BEACON) {
            revert OrchestratorBeaconMismatch(ST0X_ORCHESTRATOR_BEACON, beacon);
        }

        address impl = IBeacon(beacon).implementation();
        if (impl != LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30) {
            revert OrchestratorBeaconImplMismatch(LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30, impl);
        }

        LibMigrationInvariant.assertMigration(
            "ST0X_ORCHESTRATOR_BEACON.owner()",
            Ownable(beacon).owner(),
            LibProdDeployV4.BEACON_INITIAL_OWNER,
            chainSafe,
            ST0X_ORCHESTRATOR_BEACON_OWNER_MIGRATION_DEADLINE
        );
    }

    /// @notice Assert the pinned orchestrator instance on the active chain:
    /// it has code, `expectedAdmin` holds `DEFAULT_ADMIN_ROLE`, and its
    /// vault-logic version lock passes (so `mint`/`burn` are operable).
    /// @param expectedAdmin The address that must hold `DEFAULT_ADMIN_ROLE`,
    /// the chain's token-owner Safe.
    function assertInstance(address expectedAdmin) internal view {
        address instance = ST0X_ORCHESTRATOR_INSTANCE;
        if (instance.code.length == 0) {
            revert OrchestratorInstanceMissing(instance);
        }
        // DEFAULT_ADMIN_ROLE is 0x00 in OZ AccessControl.
        if (!IAccessControl(instance).hasRole(bytes32(0), expectedAdmin)) {
            revert OrchestratorAdminMissing(instance, expectedAdmin);
        }
        if (!IST0xOrchestratorV1(instance).vaultLogicIsExpected()) {
            revert OrchestratorVaultLogicUnexpected(instance);
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
