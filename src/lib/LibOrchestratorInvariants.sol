// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";
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

/// @notice The orchestrator beacon does not point at the audited 0.1.30
/// orchestrator implementation.
/// @param expected The pinned 0.1.30 implementation.
/// @param actual The implementation the beacon reports.
error OrchestratorBeaconImplMismatch(address expected, address actual);

/// @notice The orchestrator beacon's owner is not the chain's token-owner
/// Safe. The `20260818-migrate-orchestrator-beacon-owner` migration
/// executed on every chain (2026-09-04), so any other owner — including a
/// transfer back to the deploy EOA — is unsanctioned drift.
/// @param expected The chain's token-owner Safe.
/// @param actual The owner the beacon reports.
error OrchestratorBeaconOwnerMismatch(address expected, address actual);

/// @notice The pinned orchestrator instance has no runtime code on the
/// active chain.
/// @param instance The pinned instance address.
error OrchestratorInstanceMissing(address instance);

/// @notice The expected admin does not hold `DEFAULT_ADMIN_ROLE` on the
/// orchestrator instance. An instance without the chain's Safe as admin is
/// ungovernable (or governed by the wrong key).
/// @param instance The orchestrator instance inspected.
/// @param expectedAdmin The address that must hold `DEFAULT_ADMIN_ROLE`.
error OrchestratorAdminMissing(address instance, address expectedAdmin);

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
    /// 0.1.30 beacon-set deployer is live, reports the pinned beacon, and the
    /// beacon points at the audited 0.1.30 orchestrator implementation
    /// under the chain's token-owner Safe (the executed
    /// `20260818-migrate-orchestrator-beacon-owner` end-state).
    /// @param chainSafe The chain's token-owner Safe — the beacon owner.
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

        address owner = Ownable(beacon).owner();
        if (owner != chainSafe) {
            revert OrchestratorBeaconOwnerMismatch(chainSafe, owner);
        }
    }

    /// @notice Assert the pinned orchestrator instance on the active chain:
    /// it has code, `expectedAdmin` holds `DEFAULT_ADMIN_ROLE`, and its
    /// vault-logic version lock passes (so `mint`/`burn` are operable).
    /// @param expectedAdmin The address that must hold `DEFAULT_ADMIN_ROLE`
    /// — the chain's token-owner Safe.
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
}

/// @dev Local mirror of the set deployer's `iOrchestratorBeacon` immutable
/// getter — `IST0xOrchestratorBeaconSetDeployerV1` carries only the
/// `deploy` surface, and the getter is a concrete-contract detail the
/// interface deliberately omits.
interface ST0xOrchestratorBeaconSetDeployerLike {
    function iOrchestratorBeacon() external view returns (IBeacon);
}
